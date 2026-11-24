"""F2, an episteme reader: BM25 fused with an attention ranker (model.py).

It speaks the reader protocol: GET /health, and POST /v1/chat/completions
for one shard (the messages of src/read.bend Read.request), answered with
{"ids": [...]}. Before a question's reads, episteme posts the run notice
POST /v1/episteme/run {"question", "shards": [{"source", "n"}, ...]}: F2 then
ranks every paragraph of the run's shards together and takes them best
first until BUDGET tokens (characters / 2.55), or until the notice's "depth"
when the question says one that is less (laws/DepthLimitsARankedRun.bend: a
caller that reads only what is printed has the run sifted no deeper, and
episteme then reads fewer shards from their files), and answers "ranked": true
when its store held every named shard, with "states", how many of the
run's shard states it found on the GPU, in RAM, on disk, or had to prefill,
and how many it did not need ("kept"), and with "reads", every shard's
share of the run in the notice's order, each the string a read's reply
holds: {"ids": [...], "ranks": [...]}, beside each label its place among
those the run took, 1 the best. episteme takes those and asks for no shard
(laws/NoticeAnswerTellsReads.bend); one that does not know "reads" reads
each shard by name, POST /v1/episteme/read {"question", "source", "n"},
without its text (laws/RankedReadNamesShard.bend), and each read answers
the same share in the chat completion's shape. episteme prints the
best ranked that fit its own budget (config.json's budget_tokens) and keeps
all of them in run files (laws/BestRankedArePrinted.bend), so BUDGET is how
deep a question can be sifted, not how much it prints. A shard read with no
notice is ranked alone, with SHARD_BUDGET.

A question that names authors (laws/AuthorKeepsNamedAuthors.bend) has them
in its notice, "authors": [...]: the run is scored as any other, over every
paragraph, and the budget is then filled only from paragraphs whose record
is by one of them, so a speaker with a hundredth of the text still gets the
whole budget. Of those, a paragraph is taken only when its attention score,
before it is put in standard units, is at least FLOOR: the question draws
that much more attention to it than the null does. One speaker's lines in a
source are few and short, and without a floor the budget fills with most of
them whatever was asked; with it a question the speaker never spoke to gets
little, sometimes nothing, and episteme then delivers no excerpt. FLOOR is
in the units of the word nulls' score (WORDNULLS above 0). A question that
names no author has no floor: there it cuts the weaker paragraphs beside a
strong one, which an answer of several paragraphs needs.

The ranking fuses two scores of each paragraph: BM25 (k1 1.2, b 0.75,
lowercase words, light suffix stemming), and the attention score minus the
same score for the question "N/A", over sqrt(paragraph characters). Each is
put in standard units over the run's paragraphs (less its mean, over its
standard deviation) and the fused score is BM25's plus WEIGHT times the
attention's, so a paragraph a channel singles out stays ahead of one it
merely ranks next. Each paragraph's fused score then gains NEIGHBOUR times
the better of its two neighbours' in the shard, and after that SHARD times
the best score in its shard.

Taking them best first, a paragraph that repeats one already taken is passed
over and the budget goes to the next: both of REPEAT_WORDS words or more, and
the same words in the same order but for at most one in fifty of the longer's
(REPEAT 0.98). A record holds the same text many times over (one brief sent
to several agents, a line that opens every session, a notice printed in every
volume), and the best-scored copy says it once. The test is strict because a
looser one drops statements: two lines that differ in one word of ten (a
commit that moves a pin to another version, "both can" against "neither
can") say different things, and a short line said twice was said twice.
REPEAT 0 takes every paragraph.

A shard's attention scores for a question are kept (the last SCORES
shard-and-question pairs, a few hundred bytes each): the same question over
the same shard text scores the same, so asked again it needs neither the
shard's state nor a pass of the model, and a question asked each hour of a
source that grows costs its new shards only. A run of one shard keeps its
scores apart, its null being another (see wordnull). The server writes them
to F2_SCORES when it is told to stop and every ten minutes they have changed,
and reads them at its start, so a restart does not cost each standing
question a cold read of every state; a file by another model, other nulls
or another version of this code is left unread.

The same file says which shards were asked about last, whatever made it.
A reader that starts reads their states back from disk into RAM, the last
asked first, until RAM_GB is full (WARM 0 reads none back): a first
question over a large source is nothing but the reading of its states
(a quarter of a second each from a hard disk, two minutes for 448), and
after a restart every question would be a first one. It reads one state at
a time on its own thread and stands back while a run is being scored, so a
question asked meanwhile has the disk; a state whose word null is not kept
yet is left for the run that makes it.

A shard's state (model.prefill: the keys and values of the layers a
question reads the shard in, and its linear-attention states) is kept on
the GPU unpacked (CACHE_GB), then in host RAM packed (RAM_GB), then on disk
as those packed bytes under F2_STATES; a miss everywhere is a prefill.
Packed, a state is one run of bytes (model.py), the same in its file, in
RAM and on its way to the GPU; the unpacked states are f2pass's, on the
device, and this process holds each by a handle.

A first question over a large source is the reading of its states, so its
time is their bytes. With a book (F2_BOOK, made once by fit.py from shards
of the store) a state's keys and values are coded together at a few bits a
channel (joint.py), about a third of the bytes; it is unpacked as it
reaches the GPU, where a kept state is held as int8 either way, so a
question over states the GPU holds costs what it did. A state leaving the
GPU is dropped (RAM keeps the packed one it was unpacked from while it has
room, and the disk has it). A state's name on disk is its shard text's,
the model's, the book's and this layout's (names.py): states kept under
another book or by a reader that laid them out otherwise are not read, and
their shards are read anew.
A state is written beside its file, flushed to the disk and then renamed,
and a file that is empty or not a state counts as a miss.
A run scores the shards whose state is on the GPU first, then those in RAM,
then the rest; a reader thread stages the states the GPU lacks up to AHEAD
ahead (read from disk if RAM lacks them, and sent to the GPU by f2pass
through a pinned slab on a stream of its own) while the GPU scores; eviction takes the least
recently used state no run being scored reads later. A run bigger than the
tiers so hits what they hold, where a fixed order under plain LRU evicts
each state just before it is needed and never hits. When a state in RAM
is needed and the GPU holds only states the runs being scored have read, it
is scored from a copy that is not kept: promoting it would push one of
their own states out, and the next question would bring that one up
again. Such a copy is unpacked no further than the pass needs (with a book:
to half precision, not on to the tier's int8). RAM keeps the packed copy
of a state it hands to the GPU, and of one read from disk while it has
room; it evicts those copies first.

The scoring is done in passes (model.tail), the GPU lock held for one pass
at a time: up to BATCH shards, each scored for several questions at once.
A pass is led by one run, for its next shards, and takes with it the other
runs that wait for the same shards, so questions asked together of one
source (a caller that sends eight at once) share each state's reading and
unpacking and are scored in the same passes, a shard's keys and values held
once for all of them; a run of another source leads its own passes between
(a first question over a large source prefills for minutes, and neither
waits for the other to end). Each run still gets a score for every shard
it names, as if it had scored them alone. A pass holds at most PASS tokens
of questions' tails over its shards and questions together (the memory a
pass takes grows with them), so the more questions wait, the fewer shards a
pass takes.

What a question needs of its shards that does not depend on the question is
kept from one question to the next: the shards as read from the store
(SHARDS_MAX of them, each while its file stays as it was), each shard's words
with the paragraphs that hold them (TERMS_MAX shards; BM25 visits only the
paragraphs that hold a word of the question), and the paragraphs of the
LOTS sets of shards asked about last, each set with the paragraphs of the
words asked of it laid in arrays (WORDS_MB of them a set, those asked
last): a word's share of BM25 is then one sum in f2pass, made with the
interpreter's lock let go, so that the questions of a round sum theirs
beside each other and not in turn.

Host copies are plain pageable memory, never pinned (only the SLABS slabs
of SLAB_MB a state passes through on its way to the GPU are, in f2pass).
At most SAVES new states wait for the disk writer; a prefill past that
waits for a slot, so the queue cannot hold states RAM_GB evicted.

Setup: this directory is a uv project (pyproject.toml, uv.lock). With the
CUDA 12 toolkit's bin first on PATH,
  UV_PROJECT_ENVIRONMENT=<venv> uv sync --no-editable
makes the venv (the tokenizer's library and little else) and builds into it
f2pass, which runs the model and holds, packs and unpacks the states, in
C++ and CUDA (native/, meson.build); run it again after a change under
native/. There is no PyTorch in it: fit.py alone uses it (--group fit). The
weights:
  uvx --from huggingface_hub hf download Qwen/Qwen3.5-0.8B --local-dir $EPISTEME_HOME/f2/qwen08
(of which the reader reads the safetensors file and tokenizer.json).
Run: EPISTEME_HOME=... <venv>/bin/python f2serve.py, then point config.json's
pool at http://127.0.0.1:<PORT>. One CUDA GPU with about 10 GB at the defaults.
Once the store has shards, EPISTEME_HOME=... python fit.py (reader stopped,
a few minutes, in an environment made with --group fit) makes the book;
start the reader again after it.
No state is removed here: EPISTEME_HOME=... python prune.py removes those
no shard of the store names any more (names.py says the names).
MALLOC_MMAP_THRESHOLD_=1048576 returns freed host states to the OS, and
GLIBC_TUNABLES=glibc.malloc.hugetlb=1 backs them with huge pages, which
makes a copy off the GPU ~30% faster.

Under a cgroup memory.high (a systemd unit's MemoryHigh=) the RAM tier is
cut to that limit less HEADROOM_GB: a process over memory.high is throttled
until it barely answers, and it also evicts whenever the process's resident
memory is within MARGIN_GB of the limit, since what the process holds beyond
the tier varies.

env: EPISTEME_HOME, PORT (18112), WARM (1), BUDGET (32000), SHARD_BUDGET (120),
CACHE_GB (7), RAM_GB (24), HEADROOM_GB (8), MARGIN_GB (2), SAVES (4), AHEAD (8), SLABS (12), SLAB_MB (64), TERMS_MAX (4096), WORDS_MB (64), SHARDS_MAX (2048), LOTS (4), SCORES (65536), BATCH (8), PASS (768), WEIGHT (0.3), NEIGHBOUR (0.4), FLOOR (0.001), SHARD (0.2), REPEAT (0.98), REPEAT_WORDS (8), F2_MODEL ($EPISTEME_HOME/f2/qwen08),
F2_STATES ($EPISTEME_HOME/f2/states), F2_SCORES ($EPISTEME_HOME/f2/scores.f2), F2_BOOK ($EPISTEME_HOME/f2/book.f2).
"""
import array, collections, ctypes, difflib, hashlib, itertools, json, math, os, random, re, signal, struct, sys, threading, time, traceback
from multiprocessing.pool import ThreadPool
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# A tail pass takes temporaries whose sizes follow the batch's longest shard
# and the question's length, so no two passes ask for the same blocks; the
# stock allocator keeps each size it has handed out and the card fills with
# blocks nothing uses.
# Expandable segments hand a freed block's pages to the next size.
import f2pass
import store
import names
import model

PORT = int(os.environ.get("PORT", "18112"))
BUDGET = float(os.environ.get("BUDGET", "32000"))
SHARD_BUDGET = float(os.environ.get("SHARD_BUDGET", "120"))
CACHE_BYTES = float(os.environ.get("CACHE_GB", "7")) * 1e9
RAM_BYTES = float(os.environ.get("RAM_GB", "24")) * 1e9
HEADROOM = float(os.environ.get("HEADROOM_GB", "8")) * 1e9
MARGIN = float(os.environ.get("MARGIN_GB", "2")) * 1e9
HIGH = None  # this process's memory.high in bytes, set at startup
PAGE = os.sysconf("SC_PAGE_SIZE")
SAVES = int(os.environ.get("SAVES", "4"))
AHEAD = int(os.environ.get("AHEAD", "8"))
WORDNULLS = int(os.environ.get("WORDNULLS", "6"))
NULL = float(os.environ.get("NULL", "1.6"))
TERMS_MAX = int(os.environ.get("TERMS_MAX", "4096"))
WORDS_BYTES = float(os.environ.get("WORDS_MB", "64")) * 1048576
BATCH = int(os.environ.get("BATCH", "8"))
PASS = min(int(os.environ.get("PASS", "768")), model.TOKENS)
LOTS_MAX = int(os.environ.get("LOTS", "4"))
SCORES_MAX = int(os.environ.get("SCORES", "65536"))
WEIGHT = float(os.environ.get("WEIGHT", "0.3"))
NEIGHBOUR = float(os.environ.get("NEIGHBOUR", "0.4"))
FLOOR = float(os.environ.get("FLOOR", "0.001"))
SHARD = float(os.environ.get("SHARD", "0.2"))
REPEAT = float(os.environ.get("REPEAT", "0.98"))
REPEAT_WORDS = int(os.environ.get("REPEAT_WORDS", "8"))
STATES_DIR, WN_DIR = names.STATES_DIR, names.WN_DIR
SCORES_PATH = os.environ.get("F2_SCORES") or store.HOME + "/f2/scores.f2"
WARM = int(os.environ.get("WARM", "1"))
CHARS_PER_TOKEN = 2.55
GPU = threading.Lock()  # the model, the state tiers, ASKING and STAGED: held for one pass at a time
META = threading.RLock()  # TERMS, LOTS, SCORES, RUNS and the store
WANT = [0]  # runs waiting for or holding the GPU lock
BUSY = [0]  # runs being scored


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


def said(text):
    """a paragraph's words as written, lowercase, in order"""
    return re.findall(r"[a-z0-9]+", text.lower())


def repeats(a, b):
    """whether word lists a and b say the same thing over: each of
    REPEAT_WORDS words or more, and the same words in the same order but for
    at most a share 1 - REPEAT of the longer's"""
    n, m = sorted((len(a), len(b)))
    if REPEAT <= 0 or n < REPEAT_WORDS or n < REPEAT * m:
        return False
    if a == b:
        return True
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    if sm.quick_ratio() * (n + m) / 2 < REPEAT * m:  # too few words in common, whatever their order
        return False
    return sum(x.size for x in sm.get_matching_blocks()) >= REPEAT * m


key = names.key


def key_of(sh):
    """a shard's key, worked out once for a shard the store keeps read"""
    return sh.get("key") or sh.setdefault("key", key(sh["text"]))


def roots(sh):
    """the square roots of a shard's paragraphs' lengths in characters, at
    least 1: what a paragraph's attention score is taken over"""
    if "roots" not in sh:
        sh["roots"] = array.array("f", [math.sqrt(max(x[2], 1)) for x in sh["spans"]])
    return sh["roots"]


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


def rss():
    """this process's resident and shared (pinned shows as shared) GB"""
    f = dict(l.split(":", 1) for l in open("/proc/self/status") if ":" in l)
    return {k: int(f[k].split()[0]) / 1e6 for k in ("VmRSS", "RssShmem")}


def write(data, path):
    """bytes saved at path whole or not at all: written beside it, flushed
    to the disk, then renamed. Renamed without the flush, a file whose
    blocks had not reached the disk when the host went down comes back empty"""
    with open(path + ".tmp", "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(path + ".tmp", path)


def kept(path):
    """whether path holds a saved object: a file that is not empty"""
    try:
        return os.path.getsize(path) > 0
    except OSError:
        return False


NULLS = b"F2NULL1\n"  # a null vector's file opens with it: then its floats


def floats(path):
    """the null vector kept at path"""
    raw = open(path, "rb").read()
    if raw[:8] != NULLS:
        raise ValueError("%s is not a null vector's file" % path)
    return array.array("f", raw[8:])


class States:
    """shard states and the scores taken from theirs (their nulls): on the
    GPU unpacked (model.State), then in host RAM packed (bytes), then on
    disk as those bytes"""

    def __init__(self):
        self.gpu, self.ram = collections.OrderedDict(), collections.OrderedDict()
        self.gpu_b = self.ram_b = 0
        self.n = collections.Counter()
        self.used = {}  # GPU key -> the run that read it last
        os.makedirs(STATES_DIR, exist_ok=True)
        self.writer = ThreadPool(1)
        self.reader = ThreadPool(1)
        self.slots = threading.BoundedSemaphore(SAVES)

    def path(self, k):
        return names.state(k)

    @staticmethod
    def victim(tier, keep):
        """the least recently used key not in keep, else the least recently used"""
        return next((k for k in tier if k not in keep), next(iter(tier)))

    def put_gpu(self, k, st, size, keep=()):
        """an evicted state is dropped: RAM has the packed one it was
        unpacked from while it has room, and the disk has it"""
        self.gpu[k] = (st, size)
        self.gpu_b += size
        while self.gpu_b > CACHE_BYTES and len(self.gpu) > 1:
            k2 = self.victim(self.gpu, keep | {k})
            self.gpu_b -= self.gpu.pop(k2)[1]
            self.used.pop(k2, None)

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
        """a host copy of a state read from disk kept in RAM, if RAM has the
        room once it gives up host copies of states the GPU holds: one kept
        of a state going to the GPU makes its later eviction cost nothing,
        and one of a state scored in passing saves its next read from disk"""
        if k in self.ram:
            return
        while self.ram_b + size > RAM_BYTES or tight():
            dup = next((x for x in self.ram if x in self.gpu), None)
            if dup is None:
                break
            self.ram_b -= self.ram.pop(dup)[1]
        if self.ram_b + size <= RAM_BYTES and not tight():
            self.ram[k] = (st, size)
            self.ram_b += size

    def save(self, k, blob):
        try:
            write(blob, self.path(k))
        finally:
            self.slots.release()

    @staticmethod
    def null_path(k):
        return names.null(k)

    def kept(self, k):
        """whether disk holds k's state: an empty file is not one"""
        return kept(self.path(k))

    def load(self, k):
        """k's packed state and the "N/A" score kept in it, from disk"""
        blob = open(self.path(k), "rb").read()
        return blob, model.null(blob)

    def stage(self, k):
        """k's packed state as the host holds it (from RAM, else read from
        disk), its null, its ticket on the way to the GPU (f2pass lays it in
        a pinned slab and sends it on a stream of its own, so the transfer
        runs while the GPU scores other shards), and whether RAM had it"""
        got = self.ram.get(k)
        blob, null = got[0] if got is not None else self.load(k)
        return blob, null, model.stage(blob), got is not None

    def prefetch(self, k):
        """k's state staged on the reader thread: read from disk if RAM
        lacks it, and sent to the GPU, while the GPU scores other shards"""
        return self.reader.apply_async(self.stage, (k,))

    def wordnull(self, k, state, na, pool):
        """the vector taken from k's scores: NULL times the mean score of
        WORDNULLS nulls in the shape of a question, "What about <8 words>?",
        the words drawn from pool (words of the run's shards) by a seed that
        is the shard's key; kept in a file beside the state. With no words to
        draw, or WORDNULLS 0, it is the "N/A" score na"""
        if WORDNULLS <= 0:
            return na
        path = self.null_path(k)
        try:
            if kept(path):
                return floats(path)
        except (OSError, ValueError):  # not a null vector's file: made again
            pass
        words = pool() if pool is not None else []
        if len(words) < 64:
            return na
        rnd = random.Random(k)
        qs = ["What about " + " ".join(rnd.choice(words) for _ in range(8)) + "?" for _ in range(WORDNULLS)]
        rows = model.tail([state], qs)[0]
        wn = array.array("f", [NULL * sum(x) / len(rows) for x in zip(*rows)])
        write(NULLS + wn.tobytes(), path)
        return wn

    def own(self, k, size, keep, among):
        """whether putting k on the GPU would evict a state one of the runs
        being scored (among, their numbers) has read: the GPU then holds
        only those runs' own states, and k is scored from a copy that is not
        kept, the tiers left as they are"""
        return (bool(among) and bool(self.gpu) and self.gpu_b + size > CACHE_BYTES
                and self.used.get(self.victim(self.gpu, keep | {k})) in among)

    def get(self, k, shard, keep=frozenset(), loading=None, run=None, pool=None, among=None):
        """k's state on the GPU and its null; eviction spares the keys in
        keep (those the runs being scored read later) while any other state
        is resident. loading is a prefetch of k, if one was started; run
        numbers the run that asks, among the runs being scored with it
        (itself when not said)"""
        among = among if among is not None else frozenset() if run is None else frozenset((run,))
        if k in self.gpu:
            self.gpu.move_to_end(k)
            self.used[k] = run
            self.n["gpu"] += 1
            return self.gpu[k][0]
        try:  # a file that is not a state (cut short, another layout's) is a miss like an empty one: the shard is read anew
            if loading is not None:
                have = loading.get()
            elif k in self.ram:
                have = self.ram[k][0] + (None, True)
            else:
                have = self.load(k) + (None, False) if self.kept(k) else None
        except (OSError, ValueError):
            have = None
        if have is not None:
            blob, null, ticket, had = have
            if k in self.ram:
                self.ram.move_to_end(k)
            size = model.unpacked(blob)
            passing = self.own(k, size, keep, among)
            there = model.take(ticket, blob, kept=not passing) if ticket is not None else model.unpack(blob, kept=not passing)
            if not had:  # from disk: the null the file holds is its "N/A" score
                null = self.wordnull(k, there, null, pool)
            self.n["ram" if had else "disk"] += 1
            st = (there, null)
            if passing:
                if RAM_BYTES > 0 and k not in self.ram:  # into RAM as a state leaving the GPU would go: over what the run does not read later
                    self.put_ram(k, (blob, null), len(blob), keep)
                return st
            self.spare(k, (blob, null), len(blob))
        else:
            fresh = model.prefill(shard)
            there = model.unpack(fresh)
            na = model.scores(there, "N/A")
            model.null(fresh, na)
            blob = bytes(fresh)
            st, size = (there, self.wordnull(k, there, na, pool)), there.size
            self.n["prefill"] += 1
            self.slots.acquire()
            self.writer.apply_async(self.save, (k, blob))
            self.spare(k, (blob, st[1]), len(blob))
        self.put_gpu(k, st, size, keep)
        self.used[k] = run
        return st


TERMS = collections.OrderedDict()  # shard key -> its words' paragraphs and its paragraphs' lengths


def terms(k, sh):
    """a shard's words: for each word (stemmed) the paragraphs that hold it,
    as (paragraph, from 0; how many times) pairs in paragraph order, and each
    paragraph's length in words. Kept for the TERMS_MAX shards used last: a
    question re-reads the shards the last one did"""
    with META:
        if k in TERMS:
            TERMS.move_to_end(k)
            return TERMS[k]
    held, lengths = {}, []
    for i, (x, y, _) in enumerate(sh["spans"]):
        counts = collections.Counter(words(sh["text"][x:y]))
        lengths.append(sum(counts.values()))
        for w, c in counts.items():
            held.setdefault(w, []).append((i, c))
    with META:
        TERMS[k] = (held, lengths)
        while len(TERMS) > TERMS_MAX:
            TERMS.popitem(last=False)
    return held, lengths


SCORES = collections.OrderedDict()  # (shard key, question, whether the run had other shards) -> its paragraphs' attention scores
CHANGED = [False]  # whether SCORES holds a score its file lacks
KEEPING = threading.Lock()  # one writer of the scores' file at a time


HERE = os.path.dirname(os.path.abspath(__file__))
CODE = hashlib.sha1(b"".join(open(os.path.join(HERE, f), "rb").read() for f in ("f2serve.py", "model.py"))).hexdigest()


def made_by():
    """what a kept score depends on besides the shard's text and the
    question: the model, the nulls, this reader's code as it was read when
    the process began, and what runs its tail passes (a change to how a
    score is made must not find the scores the old code made)"""
    return [model.VERSION, WORDNULLS, NULL, CODE, model.by()]


KEPT = b"F2SCORE1"  # the kept scores' file opens with it


def keep(path):
    """the kept scores written at path, least recently used first: after
    KEPT and a length, JSON of what made them, their keys and their
    lengths, then the scores end to end as floats"""
    with KEEPING:
        with META:
            items, CHANGED[0] = list(SCORES.items()), False
        if items:
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            said = json.dumps({"by": made_by(), "keys": [k for k, _ in items], "lens": [len(v) for _, v in items]}).encode()
            write(KEPT + struct.pack("<Q", len(said)) + said + b"".join(v.tobytes() for _, v in items), path)


def kept_scores(path):
    """what keep wrote at path: what it said, and the scores end to end"""
    raw = open(path, "rb").read()
    if raw[:8] != KEPT:
        raise ValueError("not a file of kept scores")
    n = struct.unpack_from("<Q", raw, 8)[0]
    return json.loads(raw[16:16 + n]), array.array("f", raw[16 + n:])


def recall(path):
    """the scores kept at path taken into SCORES; how many. A file that is
    missing, empty, unreadable or not made by this model, these nulls and
    this code gives none"""
    if not kept(path):
        return 0
    try:
        d, flat = kept_scores(path)
        if d["by"] != made_by():
            return 0
        at, got = 0, []
        for k, n in zip(d["keys"], d["lens"]):
            got.append((tuple(k), flat[at:at + n]))
            at += n
    except Exception:
        return 0
    with META:
        for k, v in got[-SCORES_MAX:] if SCORES_MAX > 0 else []:
            SCORES[k] = v
        return len(SCORES)


def lately(path):
    """the keys of the shards the scores kept at path are of, the last
    asked first, each once; none when the file is missing or unreadable.
    Unlike recall it takes a file made by any model, nulls or code: a
    shard's key is its text's"""
    if not kept(path):
        return []
    try:
        keys = kept_scores(path)[0]["keys"]
    except Exception:
        return []
    return list(dict.fromkeys(k[0] for k in reversed(keys)))


def rewarm(keys):
    """the kept states of the shards keys, in that order, read into RAM
    until it is full: each read on this thread with no lock held, then put
    in the tier under the GPU lock as a run would. While a run is being
    scored (BUSY) it waits, so the run has the disk. Answers how many it
    read and their bytes"""
    n = size_all = 0
    for k in keys:
        while BUSY[0] > 0:
            time.sleep(0.05)
        wn = STATES.null_path(k)
        if k in STATES.ram or k in STATES.gpu or not kept(STATES.path(k)) or (WORDNULLS > 0 and not kept(wn)):
            continue
        try:
            blob, na = STATES.load(k)
            null = floats(wn) if WORDNULLS > 0 else na
        except Exception:
            continue
        size = len(blob)
        with Turn():
            if STATES.ram_b + size > RAM_BYTES or tight():
                break
            if k not in STATES.ram and k not in STATES.gpu:
                STATES.ram[k] = ((blob, null), size)
                STATES.ram_b += size
                n, size_all = n + 1, size_all + size
    return n, size_all


def rewarming(path):
    t0 = time.time()
    n, size = rewarm(lately(path))
    if n:
        print("read back %d states, %.1f GB, in %.0f s" % (n, size / 1e9, time.time() - t0), flush=True)


def keeper(path, every=600):
    """the scores written every `every` seconds they have changed"""
    while True:
        time.sleep(every)
        if CHANGED[0]:
            try:
                keep(path)
            except OSError:
                pass


def stop(*_):
    """told to stop: the scores written, then out"""
    try:
        if CHANGED[0]:
            keep(SCORES_PATH)
    finally:
        os._exit(0)


SERIAL = itertools.count()  # a number for each run
ASKING = {}  # run number -> a run whose shards are being scored
STAGED = {}  # shard key -> its state on the way to the GPU (States.prefetch), for the pass that reads it first
LOTS = collections.OrderedDict()  # shard keys -> the Lot of those shards, for the LOTS_MAX sets asked about last
MAKING = threading.Lock()  # one Lot made at a time


class Lot:
    """what some shards give every question asked of them: their paragraphs
    in order and what BM25 counts over them. A source is asked about again
    and again, by several questions at once, and none of this depends on the
    question"""

    def __init__(self, shards, keys):
        self.paras = []  # (shard index, label number, characters, start and end in the shard's text)
        self.authors = []  # each paragraph's author, None for a shard known by its text alone
        self.first, self.held, self.dl = [], [], []  # each shard's first paragraph, its words (terms); each paragraph's length in words
        for si, (k, sh) in enumerate(zip(keys, shards)):
            self.first.append(len(self.paras))
            for li, (x, y, n) in enumerate(sh["spans"]):
                self.paras.append((si, li + 1, n, x, y))
            self.authors += sh.get("authors") or [None] * len(sh["spans"])
            held, lengths = terms(k, sh)
            self.held.append(held)
            self.dl += lengths
        self.avg = sum(self.dl) / max(len(self.dl), 1)
        self.shard = f2pass.ints([p[0] for p in self.paras])
        self.words = None
        self.post, self.post_b = collections.OrderedDict(), 0  # word -> its paragraphs here (posted), and their bytes

    def posted(self, w):
        """the paragraphs of these shards that hold the word w, as BM25
        sums them (f2pass.words): their places, how often each holds it,
        and what its count is taken over there (the count plus 1.2 times
        0.25 + 0.75 of the paragraph's length over the mean), as arrays of
        ints, ints and doubles; None for a word none holds. Kept for the
        words asked last, up to WORDS_BYTES: the words most paragraphs hold
        are the ones most questions say"""
        with META:
            got = self.post.get(w)
            if got is not None:
                self.post.move_to_end(w)
                return got
        at, tf, under = array.array("i"), array.array("i"), array.array("d")
        for first, held in zip(self.first, self.held):
            for i, c in held.get(w, ()):
                at.append(first + i)
                tf.append(c)
                under.append(c + 1.2 * (0.25 + 0.75 * self.dl[first + i] / self.avg))
        if not at:
            return None
        got = (at, tf, under)
        with META:
            if w not in self.post:
                self.post[w] = got
                self.post_b += 16 * len(at)
                while self.post_b > WORDS_BYTES and len(self.post) > 1:
                    self.post_b -= 16 * len(self.post.popitem(last=False)[1][0])
        return got


class Run:
    """a question's shards: their paragraphs (a Lot), and where the scoring
    of them stands"""

    def __init__(self, shards):
        self.shards = shards
        self.serial = next(SERIAL)
        self.came = collections.Counter()  # where attention found each shard's state: gpu, ram, disk, prefill; kept, when its scores were kept and no state was needed
        self.keys = [key_of(s) for s in shards]
        if len(shards) < 2:  # a shard read alone: made as it is asked, and no set of shards gives up its place for it
            self.lot = Lot(shards, self.keys)
            return
        with MAKING:  # questions asked at once of one source make its Lot once
            with META:
                self.lot = LOTS.get(tuple(self.keys))
            if self.lot is None:
                self.lot = Lot(shards, self.keys)
            with META:
                LOTS[tuple(self.keys)] = self.lot
                LOTS.move_to_end(tuple(self.keys))
                while len(LOTS) > LOTS_MAX:
                    LOTS.popitem(last=False)

    def pool(self):
        """words (letters only, 4 or more, lowercase) of up to eight of the
        run's shards, spread evenly: what the word nulls draw from. A run of
        one shard gives none, so that a shard's null is never drawn from the
        shard alone"""
        if len(self.shards) < 2:
            return []
        if self.lot.words is None:
            step = max(1, len(self.shards) // 8)
            self.lot.words = [w.lower() for sh in self.shards[::step][:8] for w in re.findall(r"[A-Za-z]{4,}", sh["text"])]
        return self.lot.words

    def bm25(self, q):
        """per paragraph (doubles, as f2pass.fuse reads them). Only the
        paragraphs that hold a word of the question are visited, through
        the lot's arrays of them, a word's share summed by f2pass"""
        lot = self.lot
        N, out = len(lot.paras), f2pass.zeros(len(lot.paras))
        for w in words(q):  # in the question's order, a word it says twice counted twice
            post = lot.posted(w)
            if post is not None:
                df = len(post[0])
                f2pass.words(post, math.log(1 + (N - df + 0.5) / (df + 0.5)), out)
        return out

    def attention(self, q):
        """per paragraph, in shard order. A shard whose scores for q are
        kept is not scored again. The rest are scored in passes of a few
        shards (turn), each led by one run and shared with the other runs
        that wait for the same shards, so several questions asked at once of
        one source cost its states' reading once and are scored together.
        This run's shards whose state is on the GPU are taken first, then
        those in RAM, then the others: a run bigger than the tiers then hits
        what they hold, where a fixed order under LRU evicts each state just
        before it is needed and never hits."""
        tier = lambda k: 0 if k in STATES.gpu else 1 if k in STATES.ram else 2
        self.q, self.many, self.got = q, len(self.shards) > 1, {}
        with META:
            for i, k in enumerate(self.keys):
                if (k, q, self.many) in SCORES:
                    SCORES.move_to_end((k, q, self.many))
                    self.got[i] = SCORES[(k, q, self.many)]
                    self.came["kept"] += 1
        self.need = {}  # shard key -> the places in the run of the shards with that text, not scored yet
        for i, k in enumerate(self.keys):
            if i not in self.got:
                self.need.setdefault(k, []).append(i)
        try:
            with Turn():
                self.order = sorted(self.need, key=tier)
                self.ahead = 0  # how far into order states have been staged
                ASKING[self.serial] = self
            while True:
                with Turn():  # one pass: another run's pass may come between two of this one's
                    if not self.need:
                        break
                    self.turn()
        finally:
            with Turn():
                ASKING.pop(self.serial, None)
                for k in [k for k in STAGED if not any(k in r.need for r in ASKING.values())]:
                    del STAGED[k]  # staged for this run alone, and it is done or has failed
        out = array.array("f")
        for i in range(len(self.shards)):
            out.extend(self.got[i])
        return out

    def stage(self, taken=()):
        """up to AHEAD of this run's next states the GPU lacks, staged for
        it by the reader thread while it works; none of taken, the shards
        the pass being made has in hand already. A run's place in its order
        lags while other runs lead the passes they share, and a state scored
        in passing is never among the GPU's, so a run that leads again would
        else stage what its pass has just unpacked, for nobody to take"""
        while len(STAGED) < AHEAD and self.ahead < len(self.order):
            k = self.order[self.ahead]
            self.ahead += 1
            if (k in self.need and k not in taken and k not in STAGED and k not in STATES.gpu
                    and (k in STATES.ram or STATES.kept(k))):
                STAGED[k] = STATES.prefetch(k)

    def turn(self):
        """one pass under the GPU lock: this run's next shards, scored for
        its question and for those of the other runs that wait for the same
        shards. The pass holds up to PASS tokens of questions' tails over all
        its shards and questions (model.together: what the questions all open
        with counted once), and at most BATCH shards; each run it serves is
        given its scores as if it had scored the shard itself"""
        mine = (k for k in self.order if k in self.need)
        first = next(mine)
        runs, qs = [self], [self.q]
        for r in ASKING.values():
            if r is not self and first in r.need and (r.q in qs or model.together(qs + [r.q]) <= PASS):
                runs.append(r)
                if r.q not in qs:
                    qs.append(r.q)
        room = max(1, min(BATCH, PASS // model.together(qs)))
        keys = [first] + list(itertools.islice((k for k in mine if all(k in r.need for r in runs)), room - 1))
        among = frozenset(ASKING)
        later = frozenset().union(*(r.need.keys() for r in ASKING.values()))  # what a run being scored still reads, this pass's shards among them
        batch, taken = [], set()
        for k in keys:
            self.stage(taken)
            taken.add(k)
            where = k in STATES.gpu and "gpu" or k in STATES.ram and "ram" or STATES.kept(k) and "disk" or "prefill"
            state, null = STATES.get(k, self.shards[self.need[k][0]], later, STAGED.pop(k, None), self.serial, self.pool, among)
            batch.append((k, state, null, where))
        self.stage(taken)
        for (k, _state, null, where), row in zip(batch, model.tail([b[1] for b in batch], qs)):
            for r in runs:
                for i in r.need.pop(k):
                    score = f2pass.less(row[qs.index(r.q)], null, roots(r.shards[i]))  # less the null, over the root: in single precision, step by step
                    r.got[i] = score
                    r.came[where] += 1
                    with META:
                        SCORES[(k, r.q, r.many)] = score
                        CHANGED[0] = True
                        while len(SCORES) > SCORES_MAX:
                            SCORES.popitem(last=False)

    def pick(self, q, budget, who=()):
        """shard key -> (label number, rank) pairs in label order, the
        paragraphs taken best first until the budget, but for a paragraph
        that repeats one taken before it, each with its place among those
        taken, from 1; with authors named in who, only paragraphs by one of
        them are taken, and of those only the ones whose attention score
        reaches FLOOR"""
        with META:
            BUSY[0] += 1
        try:
            att = self.attention(q)
        finally:
            with META:
                BUSY[0] -= 1
        lot, out = self.lot, {k: [] for k in self.keys}
        if not lot.paras:
            return out
        # the paragraphs best first: each one's word score and WEIGHT times its attention score, each over the run's
        # mean and deviation; plus NEIGHBOUR times the better of its two neighbours' in its shard (a paragraph next to
        # a strong one is likelier to bear on the question than one that stands alone); plus SHARD times the best in
        # its shard (a shard that holds a strong paragraph is likelier to hold others that bear on it)
        order = f2pass.fuse(self.bm25(q), att, lot.shard, WEIGHT, NEIGHBOUR, SHARD)
        reach = [x >= FLOOR for x in att] if who else None
        used, taken = 0.0, []
        for i in order:
            if who and (lot.authors[i] not in who or not reach[i]):
                continue
            si, label, chars, x, y = lot.paras[i]
            text = said(self.shards[si]["text"][y - chars:y])  # the line less its label
            if any(repeats(text, t) for t in taken):
                continue
            cost = chars / CHARS_PER_TOKEN
            if used + cost > budget and used > 0:
                break
            taken.append(text)
            out[self.keys[si]].append((label, len(taken)))
            used += cost
        return {k: sorted(v) for k, v in out.items()}


STATES = States()
STORE = store.Store()
RUNS = collections.OrderedDict()  # question -> ({shard key: (label number, rank) pairs}, {(source, n): shard key})


def notice(question, names, who=(), depth=None):
    """rank the run's shards, for the authors in who when any are named, and
    no deeper than depth tokens when the question says one (else BUDGET);
    answers how many of the names the store holds, where the run found
    their states, and each held shard's read (told), in the names' order"""
    with META:
        found = [((nm["source"], int(nm["n"])), STORE.shard(nm["source"], int(nm["n"]))) for nm in names]
    found = [(nm, s) for nm, s in found if s]
    shards = [s for _, s in found]
    run = Run(shards)
    picks = run.pick(question, min(BUDGET, depth) if depth else BUDGET, who) if shards else {}
    with META:
        RUNS[question] = (picks, {nm: key_of(s) for nm, s in found})
        while len(RUNS) > 64:
            RUNS.popitem(last=False)
    return len(shards), dict(run.came), [told(picks[key_of(s)]) for _, s in found]


def told(labels):
    """a shard's labels and their ranks as a read's reply holds them"""
    return json.dumps({"ids": ["p%d" % n for n, _ in labels], "ranks": [r for _, r in labels]})


def answer(text, question):
    """a shard's labels and their ranks by its text: its share of the run,
    else ranked alone"""
    k = key(text)
    with META:
        picks, _ = RUNS.get(question, ({}, {}))
    if k in picks:
        return picks[k]
    return Run([parse(text)]).pick(question, SHARD_BUDGET)[k]


def answer_named(source, n, question):
    """a shard's labels and their ranks by its own name: its share of the
    run, else ranked alone from the store; None when the store has no such
    shard"""
    with META:
        picks, names = RUNS.get(question, ({}, {}))
        k = names.get((source, n))
        if k in picks:
            return picks[k]
        sh = STORE.shard(source, n)
    return None if sh is None else Run([sh]).pick(question, SHARD_BUDGET)[key_of(sh)]


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
                            "gpu_held_gb": model.LIB.held() / 1e9,
                            "loads": dict(STATES.n), "passes": model.by(), **rss()})
        else:
            self.send(404, {"error": "not found"})

    def do_POST(self):
        try:
            if self.path == "/v1/episteme/run":
                req, t = self.body(), time.time()
                n, came, reads = notice(req["question"], req["shards"], frozenset(req.get("authors") or ()),
                                        float(req["depth"]) if req.get("depth") else None)
                ranked = n > 0 and n == len(req["shards"])
                return self.send(200, {"shards": n, "ms": round((time.time() - t) * 1000), "states": came,
                                       "ranked": ranked, **({"reads": reads} if ranked else {})})
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
            traceback.print_exc()  # the reply holds the error's first line; where it came from goes to the log
            return self.send(500, {"error": repr(e)[:300]})
        self.send(200, {"object": "chat.completion", "model": "f2",
                        "choices": [{"index": 0, "finish_reason": "stop", "message": {
                            "role": "assistant", "content": told(labels)}}],
                        "timings": {"prompt_n": 0, "prompt_ms": ms, "cache_n": 0, "predicted_ms": 0}})

    def log_message(self, fmt, *args):
        pass


class Server(ThreadingHTTPServer):
    """the HTTP server, with room for a burst of connections waiting to be
    accepted. The stock server lets five wait; a question's reads come four
    at a time from each command that asks, so a few commands at once
    overflowed that, the kernel dropped the connection requests it had no
    room for, and each dropped one was sent again a second later: every
    question asked beside others waited that second, whatever its size"""
    request_queue_size = 1024


def warm():
    """one prefill and one tail pass on a two-line shard, so the kernels are
    compiled and tuned before the first question rather than during it"""
    model.scores(model.unpack(model.prefill(parse("== warm | 0 | f2 | w\n[p1] warm up\n"))), "N/A")


if __name__ == "__main__":
    HIGH = memory_high()
    RAM_BYTES = under(RAM_BYTES, HIGH, HEADROOM)
    warm()
    had = recall(SCORES_PATH)
    threading.Thread(target=keeper, args=(SCORES_PATH,), daemon=True).start()
    if WARM and RAM_BYTES > 0:
        threading.Thread(target=rewarming, args=(SCORES_PATH,), daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print("f2 reader on 127.0.0.1:%d, RAM tier %.1f GB, %d kept scores, tail passes by %s" % (PORT, RAM_BYTES / 1e9, had, model.by()), flush=True)
    Server(("127.0.0.1", PORT), Handler).serve_forever()
