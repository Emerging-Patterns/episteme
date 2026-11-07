"""F2, an episteme reader: BM25 fused with an attention ranker (model.py).

It speaks the reader protocol: GET /health, and POST /v1/chat/completions
for one shard (the messages of src/read.bend Read.request), answered with
{"ids": [...]}. Before a question's reads, episteme posts the run notice
POST /v1/episteme/run {"question", "shards": [{"source", "n"}, ...]}: F2 then
ranks every paragraph of the run's shards together and takes them best
first until BUDGET tokens (characters / 2.55); each shard's read answers its
share. A shard read with no notice is ranked alone, with SHARD_BUDGET.

The ranking is reciprocal-rank fusion (k = 10) of BM25 (k1 1.2, b 0.75,
lowercase words, light suffix stemming) and the attention score minus the
same score for the question "N/A", over sqrt(paragraph characters).

A shard's state (model.prefill) is kept on the GPU (CACHE_GB), then in
host RAM (RAM_GB), then on disk under F2_STATES, least recently used
first out; a miss everywhere is a prefill.

Host copies are plain pageable memory, never pinned: PyTorch's caching
host allocator keeps every freed pinned block, so a pinned RAM tier grew
far past RAM_GB (50 GB RSS against RAM_GB 24 on a 642-shard book question,
2026-11-03). At most SAVES new states wait for the disk writer; a prefill
past that waits for a slot, so the queue cannot hold states RAM_GB evicted.

Setup: a Python 3.12 venv with requirements.txt, and the weights:
  huggingface-cli download Qwen/Qwen3.5-0.8B --local-dir $EPISTEME_HOME/f2/qwen08
Run: EPISTEME_HOME=... python f2serve.py, then point config.json's pool at
http://127.0.0.1:<PORT>. One CUDA GPU with about 10 GB at the defaults.

env: EPISTEME_HOME, PORT (18112), BUDGET (4000), SHARD_BUDGET (120),
CACHE_GB (7), RAM_GB (24), SAVES (4), F2_MODEL ($EPISTEME_HOME/f2/qwen08),
F2_STATES ($EPISTEME_HOME/f2/states).
"""
import collections, copy, hashlib, json, math, os, re, sys, threading, time
from multiprocessing.pool import ThreadPool
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import torch
import store
import model

PORT = int(os.environ.get("PORT", "18112"))
BUDGET = float(os.environ.get("BUDGET", "4000"))
SHARD_BUDGET = float(os.environ.get("SHARD_BUDGET", "120"))
CACHE_BYTES = float(os.environ.get("CACHE_GB", "7")) * 1e9
RAM_BYTES = float(os.environ.get("RAM_GB", "24")) * 1e9
SAVES = int(os.environ.get("SAVES", "4"))
STATES_DIR = os.environ.get("F2_STATES") or os.environ.get("DISK") or store.HOME + "/f2/states"
CHARS_PER_TOKEN = 2.55
GPU = threading.Lock()


def stem(w):
    for suf in ("ing", "edly", "ed", "es", "s", "ly"):
        if len(w) > len(suf) + 3 and w.endswith(suf):
            return w[: -len(suf)]
    return w


def words(s):
    return [stem(w) for w in re.findall(r"[a-z0-9]+", s.lower())]


def key(text):
    return hashlib.sha1(text.strip().encode()).hexdigest()


def parse(text):
    """a shard from its rendered text alone: its [pN] lines in order"""
    starts, n = [], 1
    for m in re.finditer(r"(?m)^\[p(\d+)\] ", text):
        if int(m.group(1)) == n:
            starts.append(m.start())
            n += 1
    spans = []
    for i, a in enumerate(starts):
        seg = text[a:starts[i + 1] if i + 1 < len(starts) else len(text)].rstrip("\n")
        cut = seg.find("\n== ")
        seg = seg if cut < 0 else seg[:cut]
        spans.append((a, a + len(seg), len(seg) - len("[p%d] " % (i + 1))))
    return {"path": None, "text": text, "spans": spans}


def tensors(cache):
    for layer in cache.layers:
        for name, v in list(vars(layer).items()):
            if torch.is_tensor(v):
                yield layer, name, v


def move(state, dev):
    """a state's cache tensors moved to dev, in place; to the host it is a
    blocking copy into pageable memory (a non-blocking one would be pinned)"""
    for layer, name, v in tensors(state[1]):
        setattr(layer, name, v.to(dev, non_blocking=dev != "cpu"))
    return state


def host_copy(state):
    """a copy of a state on the host, the state itself untouched: the cache
    deep-copied with each tensor swapped for a pageable host copy"""
    memo = {id(v): v.to("cpu") for _, _, v in tensors(state[1])}
    return (state[0], copy.deepcopy(state[1], memo)) + tuple(state[2:])


def rss():
    """this process's resident and shared (pinned shows as shared) GB"""
    f = dict(l.split(":", 1) for l in open("/proc/self/status") if ":" in l)
    return {k: int(f[k].split()[0]) / 1e6 for k in ("VmRSS", "RssShmem")}


def nbytes(cache):
    return sum(v.numel() * v.element_size() for layer in cache.layers
               for v in vars(layer).values() if torch.is_tensor(v))


class States:
    """shard states and their "N/A" scores: GPU, then host RAM, then disk"""

    def __init__(self):
        self.gpu, self.ram = collections.OrderedDict(), collections.OrderedDict()
        self.gpu_b = self.ram_b = 0
        self.n = collections.Counter()
        os.makedirs(STATES_DIR, exist_ok=True)
        self.writer = ThreadPool(1)
        self.slots = threading.BoundedSemaphore(SAVES)

    def path(self, k):
        return "%s/%s.pt" % (STATES_DIR, hashlib.sha1((k + model.VERSION).encode()).hexdigest())

    @staticmethod
    def victim(tier, keep):
        """the least recently used key not in keep, else the least recently used"""
        return next((k for k in tier if k not in keep), next(iter(tier)))

    def put_gpu(self, k, st, size, keep=()):
        self.gpu[k] = (st, size)
        self.gpu_b += size
        while self.gpu_b > CACHE_BYTES and len(self.gpu) > 1:
            k2 = self.victim(self.gpu, keep | {k})
            (state, null), s2 = self.gpu.pop(k2)
            self.gpu_b -= s2
            if RAM_BYTES > 0:
                self.put_ram(k2, (move(state, "cpu"), null), s2, keep)

    def put_ram(self, k, st, size, keep=()):
        self.ram[k] = (st, size)
        self.ram_b += size
        while self.ram_b > RAM_BYTES and self.ram:
            (_, s2) = self.ram.pop(self.victim(self.ram, keep))
            self.ram_b -= s2

    def save(self, k, cpu):
        try:
            tmp = self.path(k) + ".tmp"
            torch.save(cpu, tmp)
            os.replace(tmp, self.path(k))
        finally:
            self.slots.release()

    def get(self, k, shard, keep=frozenset()):
        """k's state and null; eviction spares the keys in keep (those the
        run reads later) while any other state is resident"""
        if k in self.gpu:
            self.gpu.move_to_end(k)
            self.n["gpu"] += 1
            return self.gpu[k][0]
        if k in self.ram:
            (state, null), size = self.ram.pop(k)
            self.ram_b -= size
            st = (move(state, model.DEV), null)
            self.n["ram"] += 1
        elif os.path.exists(self.path(k)):
            state, null = torch.load(self.path(k), weights_only=False)
            st, size = (move(state, model.DEV), null), nbytes(state[1])
            self.n["disk"] += 1
        else:
            state = model.prefill(shard)
            st, size = (state, model.scores(state, "N/A")), nbytes(state[1])
            self.n["prefill"] += 1
            self.slots.acquire()
            self.writer.apply_async(self.save, (k, (host_copy(state), st[1])))
        self.put_gpu(k, st, size, keep)
        return st


class Run:
    """the paragraphs of some shards, with BM25 statistics over them"""

    def __init__(self, shards):
        self.shards = shards
        self.keys = [key(s["text"]) for s in shards]
        self.paras = []  # (shard index, label number, characters, text)
        for si, sh in enumerate(shards):
            for li, (x, y, n) in enumerate(sh["spans"]):
                self.paras.append((si, li + 1, n, sh["text"][x:y]))
        docs = [words(p[3]) for p in self.paras]
        self.avg = sum(map(len, docs)) / max(len(docs), 1)
        self.df = collections.Counter(w for d in docs for w in set(d))
        self.tfs = [collections.Counter(d) for d in docs]
        self.dl = [len(d) for d in docs]

    def bm25(self, q):
        N, ws, out = len(self.paras), words(q), []
        for tf, dl in zip(self.tfs, self.dl):
            out.append(sum(math.log(1 + (N - self.df[w] + 0.5) / (self.df[w] + 0.5))
                           * tf[w] * 2.2 / (tf[w] + 1.2 * (0.25 + 0.75 * dl / self.avg))
                           for w in ws if w in tf))
        return out

    def attention(self, q):
        """per paragraph, in shard order. The shards whose state is on the GPU
        are scored first, then those in RAM, then the rest: a run bigger than
        the tiers then hits what they hold, where a fixed order under LRU
        evicts each state just before it is needed and never hits."""
        tier = lambda k: 0 if k in STATES.gpu else 1 if k in STATES.ram else 2
        order = sorted(range(len(self.shards)), key=lambda i: tier(self.keys[i]))
        left = collections.Counter(self.keys)
        got = {}
        for i in order:
            sh = self.shards[i]
            left[self.keys[i]] -= 1
            state, null = STATES.get(self.keys[i], sh, frozenset(k for k, c in left.items() if c > 0))
            v = model.scores(state, q) - null
            got[i] = (v / torch.tensor([x[2] for x in sh["spans"]], dtype=torch.float).clamp(min=1).sqrt()).tolist()
        return [x for i in range(len(self.shards)) for x in got[i]]

    def pick(self, q, budget):
        """shard key -> label numbers, best first until the budget"""
        def ranks(s):
            r = [0] * len(s)
            for k, i in enumerate(sorted(range(len(s)), key=lambda i: -s[i])):
                r[i] = k
            return r
        fused = [1 / (10 + x) + 1 / (10 + y) for x, y in zip(ranks(self.bm25(q)), ranks(self.attention(q)))]
        out, used = {k: [] for k in self.keys}, 0.0
        for i in sorted(range(len(self.paras)), key=lambda i: -fused[i]):
            cost = self.paras[i][2] / CHARS_PER_TOKEN
            if used + cost > budget and used > 0:
                break
            out[self.keys[self.paras[i][0]]].append(self.paras[i][1])
            used += cost
        return {k: sorted(v) for k, v in out.items()}


STATES = States()
STORE = store.Store()
RUNS = collections.OrderedDict()  # question -> {shard key: label numbers}


def notice(question, names):
    with GPU:
        shards = [s for s in (STORE.shard(nm["source"], int(nm["n"])) for nm in names) if s]
        RUNS[question] = Run(shards).pick(question, BUDGET) if shards else {}
        while len(RUNS) > 64:
            RUNS.popitem(last=False)
        return len(shards)


def answer(text, question):
    with GPU:
        k = key(text)
        run = RUNS.get(question)
        if run is not None and k in run:
            return run[k]
        return Run([parse(text)]).pick(question, SHARD_BUDGET)[k]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))

    def do_GET(self):
        if self.path == "/health":
            self.send(200, {"status": "ok"})
        elif self.path == "/stats":
            self.send(200, {"gpu_states": len(STATES.gpu), "gpu_gb": STATES.gpu_b / 1e9,
                            "ram_states": len(STATES.ram), "ram_gb": STATES.ram_b / 1e9,
                            "loads": dict(STATES.n), **rss()})
        else:
            self.send(404, {"error": "not found"})

    def do_POST(self):
        try:
            if self.path == "/v1/episteme/run":
                req, t = self.body(), time.time()
                n = notice(req["question"], req["shards"])
                return self.send(200, {"shards": n, "ms": round((time.time() - t) * 1000)})
            if self.path != "/v1/chat/completions":
                return self.send(404, {"error": "not found"})
            msgs, t = self.body()["messages"], time.time()
            q = msgs[2]["content"]
            labels = answer(msgs[1]["content"], q[len("Question: "):] if q.startswith("Question: ") else q)
            ms = (time.time() - t) * 1000
        except Exception as e:
            return self.send(500, {"error": repr(e)[:300]})
        self.send(200, {"object": "chat.completion", "model": "f2",
                        "choices": [{"index": 0, "finish_reason": "stop", "message": {
                            "role": "assistant", "content": json.dumps({"ids": ["p%d" % n for n in labels]})}}],
                        "timings": {"prompt_n": 0, "prompt_ms": ms, "cache_n": 0, "predicted_ms": 0}})

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print("f2 reader on 127.0.0.1:%d" % PORT, flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
