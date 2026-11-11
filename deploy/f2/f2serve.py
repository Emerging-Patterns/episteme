"""F2, an episteme reader: BM25 fused with an attention ranker (model.py).

It speaks the reader protocol: GET /health, and POST /v1/chat/completions
for one shard (the messages of src/read.bend Read.request), answered with
{"ids": [...]}. Before a question's reads, episteme posts the run notice
POST /v1/episteme/run {"question", "shards": [{"source", "n"}, ...]}: F2 then
ranks every paragraph of the run's shards together and takes them best
first until BUDGET tokens (characters / 2.55), and answers "ranked": true
when its store held every named shard. episteme then reads each shard by
name, POST /v1/episteme/read {"question", "source", "n"}, without its text
(laws/RankedReadNamesShard.bend), and each read answers the shard's share,
in the chat completion's shape. A shard read with no notice is ranked alone,
with SHARD_BUDGET.

The ranking is reciprocal-rank fusion (k = 10) of BM25 (k1 1.2, b 0.75,
lowercase words, light suffix stemming) and the attention score minus the
same score for the question "N/A", over sqrt(paragraph characters). Each
paragraph's fused score then gains NEIGHBOUR times the better of its two
neighbours' in the shard.

A shard's state (model.prefill: its keys and values int8, its
linear-attention states bf16) is kept on the GPU (CACHE_GB), then in host
RAM (RAM_GB), then on disk under F2_STATES; a miss everywhere is a prefill.
A run scores the shards whose state is on the GPU first, then those in RAM,
then the rest, which a reader thread loads from disk up to AHEAD ahead,
BATCH shards to a tail pass (model.scores_batch); eviction takes the least
recently used state the run does not read later. The GPU lock is held for
one batch at a time, so a second question's batches come between a long
run's (a first question over a large source prefills for minutes) and
neither waits for the other to end; each run still scores every shard it
names. A run bigger than the
tiers so hits what they hold, where a fixed order under plain LRU evicts
each state just before it is needed and never hits. RAM keeps the host copy
of a state it hands to the GPU, and of one read from disk while it has
room; it evicts those copies first, and a state leaving the GPU with a host
copy is dropped, not copied back.

Host copies are plain pageable memory, never pinned: PyTorch's caching
host allocator keeps every freed pinned block, so a pinned RAM tier grew
far past RAM_GB (50 GB RSS against RAM_GB 24 on a 642-shard book question,
2026-11-03). At most SAVES new states wait for the disk writer; a prefill
past that waits for a slot, so the queue cannot hold states RAM_GB evicted.

Setup: a Python 3.12 venv with requirements.txt, and the weights:
  huggingface-cli download Qwen/Qwen3.5-0.8B --local-dir $EPISTEME_HOME/f2/qwen08
Run: EPISTEME_HOME=... python f2serve.py, then point config.json's pool at
http://127.0.0.1:<PORT>. One CUDA GPU with about 10 GB at the defaults.
MALLOC_MMAP_THRESHOLD_=1048576 returns freed host states to the OS, and
GLIBC_TUNABLES=glibc.malloc.hugetlb=1 backs them with huge pages, which
makes a copy off the GPU ~30% faster.

Under a cgroup memory.high (a systemd unit's MemoryHigh=) the RAM tier is
cut to that limit less HEADROOM_GB: a process over memory.high is throttled
until it barely answers, and it also evicts whenever the process's resident
memory is within MARGIN_GB of the limit, since what the process holds beyond
the tier varies (a 24 GB tier under a 27 GiB limit stalled the
reader once two large sources were loaded, 2026-11-10: the process held
about 6 GB beyond its tier).

env: EPISTEME_HOME, PORT (18112), BUDGET (4000), SHARD_BUDGET (120),
CACHE_GB (7), RAM_GB (24), HEADROOM_GB (8), MARGIN_GB (2), SAVES (4), AHEAD (8), TERMS_MAX (1024), BATCH (8), NEIGHBOUR (0.25), F2_MODEL ($EPISTEME_HOME/f2/qwen08),
F2_STATES ($EPISTEME_HOME/f2/states).
"""
import collections, copy, ctypes, hashlib, json, math, os, re, sys, threading, time
from multiprocessing.pool import ThreadPool
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# A tail pass takes temporaries whose sizes follow the batch's longest shard
# and the question's length, so no two passes ask for the same blocks; the
# stock allocator keeps each size it has handed out and the card fills with
# blocks nothing uses (a 12 GB card at 11.5 GB with 7 GB in use, BATCH 8).
# Expandable segments hand a freed block's pages to the next size.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
import torch
import store
import model

PORT = int(os.environ.get("PORT", "18112"))
BUDGET = float(os.environ.get("BUDGET", "4000"))
SHARD_BUDGET = float(os.environ.get("SHARD_BUDGET", "120"))
CACHE_BYTES = float(os.environ.get("CACHE_GB", "7")) * 1e9
RAM_BYTES = float(os.environ.get("RAM_GB", "24")) * 1e9
HEADROOM = float(os.environ.get("HEADROOM_GB", "8")) * 1e9
MARGIN = float(os.environ.get("MARGIN_GB", "2")) * 1e9
HIGH = None  # this process's memory.high in bytes, set at startup
PAGE = os.sysconf("SC_PAGE_SIZE")
SAVES = int(os.environ.get("SAVES", "4"))
AHEAD = int(os.environ.get("AHEAD", "8"))
TERMS_MAX = int(os.environ.get("TERMS_MAX", "1024"))
BATCH = int(os.environ.get("BATCH", "8"))
NEIGHBOUR = float(os.environ.get("NEIGHBOUR", "0.25"))
STATES_DIR = os.environ.get("F2_STATES") or os.environ.get("DISK") or store.HOME + "/f2/states"
CHARS_PER_TOKEN = 2.55
GPU = threading.Lock()  # the model and the state tiers: held for one batch of shards at a time
META = threading.RLock()  # TERMS and RUNS
WANT = [0]  # runs waiting for or holding the GPU lock


class Turn:
    """the GPU lock for one batch. A run that sees another waiting when it
    lets go sleeps a moment, so the lock goes round instead of back to it"""

    def __enter__(self):
        with META:
            WANT[0] += 1
        GPU.acquire()

    def __exit__(self, *exc):
        GPU.release()
        with META:
            WANT[0] -= 1
            others = WANT[0] > 0
        if others:
            time.sleep(0.002)


def memory_high():
    """this process's cgroup memory.high in bytes, or None when there is no
    limit or no cgroup v2 file to read"""
    try:
        rel = open("/proc/self/cgroup").read().strip().rsplit("::", 1)[1]
        text = open("/sys/fs/cgroup" + rel + "/memory.high").read().strip()
        return None if text == "max" else float(text)
    except (OSError, IndexError, ValueError):
        return None


def under(ram, high, headroom):
    """the RAM tier that stays under a memory.high: above it the kernel
    throttles the process until it barely runs, so the tier leaves headroom
    for everything else the process holds (the weights' host side, Python,
    term counts, states on their way to disk)"""
    return ram if high is None else max(0.0, min(ram, high - headroom))


def resident():
    """this process's resident bytes"""
    return int(open("/proc/self/statm").read().split()[1]) * PAGE


TRIMMED = [0.0]  # when freed memory was last handed back to the system


def trim():
    """hand the allocator's freed memory back to the system, at most once
    every 5 s: a state's small tensors (its linear-attention states, under
    the mmap threshold) are freed into malloc's arenas, which keep them, so
    the process grew by gigabytes as states came and went"""
    if time.time() - TRIMMED[0] > 5:
        try:
            ctypes.CDLL("libc.so.6").malloc_trim(0)
        except (OSError, AttributeError):
            pass
        TRIMMED[0] = time.time()


def tight():
    """whether the process is within MARGIN of its memory.high, after
    handing freed memory back: what it holds beyond the RAM tier is not
    constant, so the tier also gives way to what is measured"""
    if HIGH is None or resident() <= HIGH - MARGIN:
        return False
    trim()
    return resident() > HIGH - MARGIN


def stem(w):
    for suf in ("ing", "edly", "ed", "es", "s", "ly"):
        if len(w) > len(suf) + 3 and w.endswith(suf):
            return w[: -len(suf)]
    return w


STEMS = {}  # word -> stem(word): a run's paragraphs hold millions of words, few distinct


def words(s):
    return [STEMS.get(w) or STEMS.setdefault(w, stem(w)) for w in re.findall(r"[a-z0-9]+", s.lower())]


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
    """every tensor of a cache, with a setter that replaces it: attention
    layers hold theirs as attributes, linear-attention layers in dicts"""
    for layer in cache.layers:
        for name, v in list(vars(layer).items()):
            if torch.is_tensor(v):
                yield v, lambda t, layer=layer, name=name: setattr(layer, name, t)
            elif isinstance(v, dict):
                for i, t in list(v.items()):
                    if torch.is_tensor(t):
                        yield t, lambda t2, d=v, i=i: d.__setitem__(i, t2)


def move(state, dev):
    """a state's cache tensors moved to dev, in place; to the host it is a
    blocking copy into pageable memory (a non-blocking one would be pinned)"""
    for v, put in tensors(state[1]):
        put(v.to(dev, non_blocking=dev != "cpu"))
    return state


def copy_to(state, dev):
    """a copy of a state with its cache tensors on dev, the state itself
    untouched: the cache and its layers are shallow copies holding the new
    tensors (no tail pass writes into a kept state's cache)"""
    c = copy.copy(state[1])
    c.layers = [copy.copy(layer) for layer in state[1].layers]
    for layer in c.layers:
        for name, v in list(vars(layer).items()):
            if torch.is_tensor(v):
                setattr(layer, name, v.to(dev))
            elif isinstance(v, dict):
                setattr(layer, name, {i: t.to(dev) if torch.is_tensor(t) else t for i, t in v.items()})
    return (state[0], c) + tuple(state[2:])


def host_copy(state):
    """a copy of a state on the host, the state itself untouched: the cache
    deep-copied with each tensor swapped for a pageable host copy"""
    memo = {id(v): v.to("cpu") for v, _ in tensors(state[1])}
    return (state[0], copy.deepcopy(state[1], memo)) + tuple(state[2:])


def rss():
    """this process's resident and shared (pinned shows as shared) GB"""
    f = dict(l.split(":", 1) for l in open("/proc/self/status") if ":" in l)
    return {k: int(f[k].split()[0]) / 1e6 for k in ("VmRSS", "RssShmem")}


def nbytes(cache):
    return sum(v.numel() * v.element_size() for v, _ in tensors(cache))


class States:
    """shard states and their "N/A" scores: GPU, then host RAM, then disk"""

    def __init__(self):
        self.gpu, self.ram = collections.OrderedDict(), collections.OrderedDict()
        self.gpu_b = self.ram_b = 0
        self.n = collections.Counter()
        os.makedirs(STATES_DIR, exist_ok=True)
        self.writer = ThreadPool(1)
        self.reader = ThreadPool(1)
        self.slots = threading.BoundedSemaphore(SAVES)

    def path(self, k):
        return "%s/%s.pt" % (STATES_DIR, hashlib.sha1((k + model.VERSION).encode()).hexdigest())

    @staticmethod
    def victim(tier, keep):
        """the least recently used key not in keep, else the least recently used"""
        return next((k for k in tier if k not in keep), next(iter(tier)))

    def put_gpu(self, k, st, size, keep=()):
        """an evicted state with a host copy in RAM is dropped, with none it
        is copied to RAM"""
        self.gpu[k] = (st, size)
        self.gpu_b += size
        while self.gpu_b > CACHE_BYTES and len(self.gpu) > 1:
            k2 = self.victim(self.gpu, keep | {k})
            (state, null), s2 = self.gpu.pop(k2)
            self.gpu_b -= s2
            if RAM_BYTES > 0 and k2 not in self.ram:
                self.put_ram(k2, (move(state, "cpu"), null), s2, keep)

    def put_ram(self, k, st, size, keep=()):
        """eviction takes host copies of states on the GPU first, then by
        victim: the RAM tier is spent on states the GPU lacks"""
        self.ram[k] = (st, size)
        self.ram_b += size
        while (self.ram_b > RAM_BYTES or tight()) and len(self.ram) > 1:
            k2 = next((x for x in self.ram if x in self.gpu and x != k), None)
            (_, s2) = self.ram.pop(k2 if k2 is not None else self.victim(self.ram, keep))
            self.ram_b -= s2

    def spare(self, k, st, size):
        """a host copy of a state going to the GPU kept in RAM, if RAM has the
        room without evicting: its later eviction from the GPU then copies nothing"""
        if self.ram_b + size <= RAM_BYTES and not tight():
            self.ram[k] = (st, size)
            self.ram_b += size

    def save(self, k, cpu):
        try:
            tmp = self.path(k) + ".tmp"
            torch.save(cpu, tmp)
            os.replace(tmp, self.path(k))
        finally:
            self.slots.release()

    def load(self, k):
        return torch.load(self.path(k), weights_only=False, map_location="cpu")

    def prefetch(self, k):
        """k's state read from disk to the host on the reader thread"""
        return self.reader.apply_async(self.load, (k,))

    def get(self, k, shard, keep=frozenset(), loading=None):
        """k's state and null; eviction spares the keys in keep (those the
        run reads later) while any other state is resident. loading is a
        prefetch of k from disk, if one was started"""
        if k in self.gpu:
            self.gpu.move_to_end(k)
            self.n["gpu"] += 1
            return self.gpu[k][0]
        if k in self.ram:
            (state, null), size = self.ram[k]
            self.ram.move_to_end(k)
            st = (copy_to(state, model.DEV), null)
            self.n["ram"] += 1
        elif loading is not None or os.path.exists(self.path(k)):
            state, null = loading.get() if loading is not None else self.load(k)
            st, size = (copy_to(state, model.DEV), null), nbytes(state[1])
            self.spare(k, (state, null), size)
            self.n["disk"] += 1
        else:
            state = model.prefill(shard)
            st, size = (state, model.scores(state, "N/A")), nbytes(state[1])
            self.n["prefill"] += 1
            self.slots.acquire()
            self.writer.apply_async(self.save, (k, (host_copy(state), st[1])))
        self.put_gpu(k, st, size, keep)
        return st


TERMS = collections.OrderedDict()  # shard key -> each paragraph's term counts


def terms(k, sh):
    """the term counts of a shard's paragraphs, kept for the TERMS_MAX
    shards used last: a question re-reads the shards the last one did"""
    with META:
        if k in TERMS:
            TERMS.move_to_end(k)
            return TERMS[k]
    counts = [collections.Counter(words(sh["text"][x:y])) for x, y, _ in sh["spans"]]
    with META:
        TERMS[k] = counts
        while len(TERMS) > TERMS_MAX:
            TERMS.popitem(last=False)
    return counts


class Run:
    """the paragraphs of some shards, with BM25 statistics over them"""

    def __init__(self, shards):
        self.shards = shards
        self.keys = [key(s["text"]) for s in shards]
        self.paras = []  # (shard index, label number, characters, text)
        for si, sh in enumerate(shards):
            for li, (x, y, n) in enumerate(sh["spans"]):
                self.paras.append((si, li + 1, n, sh["text"][x:y]))
        self.tfs = [tf for k, sh in zip(self.keys, shards) for tf in terms(k, sh)]
        self.dl = [sum(tf.values()) for tf in self.tfs]
        self.avg = sum(self.dl) / max(len(self.dl), 1)
        self.df = collections.Counter(w for tf in self.tfs for w in tf)

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
        with Turn():
            order = sorted(range(len(self.shards)), key=lambda i: tier(self.keys[i]))
            cold = [k for k in dict.fromkeys(self.keys[i] for i in order)
                    if tier(k) == 2 and os.path.exists(STATES.path(k))]
        loading = {}  # the next AHEAD cold states, read from disk while the GPU works
        left = collections.Counter(self.keys)
        got = {}
        for at in range(0, len(order), BATCH):
            with Turn():  # one batch: another run's batch may come between two of this one's
                batch = []
                for i in order[at:at + BATCH]:
                    while cold and len(loading) < AHEAD:
                        k = cold.pop(0)
                        loading[k] = STATES.prefetch(k)
                    left[self.keys[i]] -= 1
                    keep = frozenset([k for k, c in left.items() if c > 0] + [b[1] for b in batch])
                    state, null = STATES.get(self.keys[i], self.shards[i], keep, loading.pop(self.keys[i], None))
                    batch.append((i, self.keys[i], state, null))
                for (i, _k, _state, null), v in zip(batch, model.scores_batch([b[2] for b in batch], q)):
                    got[i] = ((v - null) / torch.tensor([x[2] for x in self.shards[i]["spans"]], dtype=torch.float).clamp(min=1).sqrt()).tolist()
        return [x for i in range(len(self.shards)) for x in got[i]]

    def spread(self, fused):
        """each paragraph's fused score plus NEIGHBOUR times the better of
        its two neighbours' in the same shard: a paragraph next to a strong
        one is likelier to bear on the question than one that stands alone"""
        out = list(fused)
        for i, p in enumerate(self.paras):
            near = [fused[j] for j in (i - 1, i + 1) if 0 <= j < len(fused) and self.paras[j][0] == p[0]]
            if near:
                out[i] += NEIGHBOUR * max(near)
        return out

    def pick(self, q, budget):
        """shard key -> label numbers, best first until the budget"""
        def ranks(s):
            r = [0] * len(s)
            for k, i in enumerate(sorted(range(len(s)), key=lambda i: -s[i])):
                r[i] = k
            return r
        fused = [1 / (10 + x) + 1 / (10 + y) for x, y in zip(ranks(self.bm25(q)), ranks(self.attention(q)))]
        fused = self.spread(fused)
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
RUNS = collections.OrderedDict()  # question -> ({shard key: label numbers}, {(source, n): shard key})


def notice(question, names):
    """rank the run's shards; answers how many of the names the store holds"""
    with META:
        found = [((nm["source"], int(nm["n"])), STORE.shard(nm["source"], int(nm["n"]))) for nm in names]
    found = [(nm, s) for nm, s in found if s]
    shards = [s for _, s in found]
    picks = Run(shards).pick(question, BUDGET) if shards else {}
    with META:
        RUNS[question] = (picks, {nm: key(s["text"]) for nm, s in found})
        while len(RUNS) > 64:
            RUNS.popitem(last=False)
    return len(shards)


def answer(text, question):
    """a shard's labels by its text: its share of the run, else ranked alone"""
    k = key(text)
    with META:
        picks, _ = RUNS.get(question, ({}, {}))
    if k in picks:
        return picks[k]
    return Run([parse(text)]).pick(question, SHARD_BUDGET)[k]


def answer_named(source, n, question):
    """a shard's labels by its own name: its share of the run, else ranked
    alone from the store; None when the store has no such shard"""
    with META:
        picks, names = RUNS.get(question, ({}, {}))
        k = names.get((source, n))
        if k in picks:
            return picks[k]
        sh = STORE.shard(source, n)
    return None if sh is None else Run([sh]).pick(question, SHARD_BUDGET)[key(sh["text"])]


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
                return self.send(200, {"shards": n, "ms": round((time.time() - t) * 1000),
                                       "ranked": n > 0 and n == len(req["shards"])})
            if self.path == "/v1/episteme/read":
                req, t = self.body(), time.time()
                labels = answer_named(req["source"], int(req["n"]), req["question"])
                if labels is None:
                    return self.send(404, {"error": "no shard %s %s" % (req["source"], req["n"])})
            elif self.path == "/v1/chat/completions":
                msgs, t = self.body()["messages"], time.time()
                q = msgs[2]["content"]
                labels = answer(msgs[1]["content"], q[len("Question: "):] if q.startswith("Question: ") else q)
            else:
                return self.send(404, {"error": "not found"})
            ms = (time.time() - t) * 1000
        except Exception as e:
            return self.send(500, {"error": repr(e)[:300]})
        self.send(200, {"object": "chat.completion", "model": "f2",
                        "choices": [{"index": 0, "finish_reason": "stop", "message": {
                            "role": "assistant", "content": json.dumps({"ids": ["p%d" % n for n in labels]})}}],
                        "timings": {"prompt_n": 0, "prompt_ms": ms, "cache_n": 0, "predicted_ms": 0}})

    def log_message(self, fmt, *args):
        pass


def warm():
    """one prefill and one tail pass on a two-line shard, so the kernels are
    compiled and tuned before the first question rather than during it"""
    model.scores(model.prefill(parse("== warm | 0 | f2 | w\n[p1] warm up\n")), "N/A")


if __name__ == "__main__":
    HIGH = memory_high()
    RAM_BYTES = under(RAM_BYTES, HIGH, HEADROOM)
    warm()
    print("f2 reader on 127.0.0.1:%d, RAM tier %.1f GB" % (PORT, RAM_BYTES / 1e9), flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
