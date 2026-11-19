"""fit.py: make the book a reader codes its states with (joint.py), from
shards of the store. Run once, with the reader stopped or on another GPU:

  EPISTEME_HOME=... python fit.py [bits]

It draws SHARDS (64) shards by a fixed seed, in turn from each kind of
source and within a kind from each corpus (a source's name up to its last
"/"), at most PER (8) of a corpus; prefills each
and takes the second moment of its tokens' rows; asks each a dozen questions
and takes the second moment of the queries that read its keys, each turned
back by the position of a key it may read; takes the metric of the values
from the model's own output projection; and writes the book for an average
of bits (3) a channel to F2_BOOK ($EPISTEME_HOME/f2/book.pt), beside it
what it was made from (<book>.json). The questions are the store's own
(the distinct questions of five words or more in telemetry.jsonl) when it
has QUESTIONS (32) of them, else made of the shard's words in the shape of
the reader's word nulls: a book weighted by real questions codes the keys
with about half a bit less error.

A reader started after this keeps its states by the new book: a state kept
before is read once more and coded when it is next asked about. A second
run makes a different book only if the store's shards or questions have
changed, and every state is then coded again from a fresh prefill, so do
not run it without need. F2_FIT_SKIP names source prefixes to leave out
(comma-separated), for fitting a book apart from the sources it is tested
on.
"""
import collections, glob, json, os, random, re, sys

OUT = os.environ.get("F2_BOOK") or (os.environ.get("EPISTEME_HOME") or os.path.expanduser("~/.local/share/episteme")) + "/f2/book.pt"
os.environ["F2_BOOK"] = os.devnull  # the model is loaded with no book: the rows are the model's own
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import torch
from transformers.models.qwen3_5.modeling_qwen3_5 import apply_rotary_pos_emb
import joint, model, store

BITS = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
PER, SHARDS, QUESTIONS = (int(os.environ.get(k, d)) for k, d in (("PER", "8"), ("SHARDS", "64"), ("QUESTIONS", "32")))
SKIP = tuple(x for x in os.environ.get("F2_FIT_SKIP", "").split(",") if x)
rnd = random.Random(11)


def draw():
    """the shards to fit on, as (corpus, shard file) pairs: taken in turn
    from each kind of source (the name up to its ":"), within a kind in turn
    from each corpus (the name up to its last "/"), at most PER of a corpus,
    so that neither a kind of many corpora nor a corpus of many shards
    crowds out the rest"""
    st = store.Store()
    st.index()
    kinds = collections.defaultdict(lambda: collections.defaultdict(list))
    for src in sorted(st.dirs):
        if not src.startswith(SKIP or ("\0",)):
            kinds[src.split(":", 1)[0]][src.rsplit("/", 1)[0]].extend(sorted(glob.glob(st.dirs[src] + "0*.json")))
    turns = []
    for kind in sorted(kinds):
        corpora = sorted(kinds[kind])
        for c in corpora:
            rnd.shuffle(kinds[kind][c])
        rnd.shuffle(corpora)
        turns.append([(c, f) for j in range(PER) for c in corpora for f in kinds[kind][c][j:j + 1]])
    picked = []
    for j in range(max(map(len, turns), default=0)):
        picked += [t[j] for t in turns if j < len(t)]
    return picked[:SHARDS]


def asked():
    """the store's own questions, distinct, of five words or more"""
    qs = set()
    try:
        for line in open(store.HOME + "/telemetry.jsonl"):
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("via") != "eval" and len(row.get("question", "").split()) >= 5:
                qs.add(row["question"])
    except OSError:
        pass
    return sorted(qs)


SEEN = {}  # "q7", "q11" -> the queries of the last tail pass, as attention used them
stock = model.grouped


def grouped(module, query, key, value, attention_mask, scaling, dropout=0.0, **kwargs):
    SEEN["q7"] = query.float()
    return stock(module, query, key, value, attention_mask, scaling, dropout, **kwargs)


def last(self, hidden_states, position_embeddings, attention_mask, past_key_values=None, **kwargs):
    if self.config._attn_implementation != "sdpa":
        shape = (*hidden_states.shape[:-1], -1, self.head_dim)
        q, _gate = torch.chunk(self.q_proj(hidden_states).view(*shape[:-1], self.head_dim * 2), 2, dim=-1)
        q = self.q_norm(q.view(shape)).transpose(1, 2)
        SEEN["q11"] = apply_rotary_pos_emb(q, q, *position_embeddings)[0].float()
    return model.last(self, hidden_states, position_embeddings, attention_mask, past_key_values, **kwargs)


model.ALL_ATTENTION_FUNCTIONS.register("grouped", grouped)
top = model.M.model.layers[model.SCALED].self_attn
top.forward = last.__get__(top)
READ = {"q7": {0: (0, 1, 2, 3), 1: (4, 5, 6, 7)},  # query heads by the key-value head they read
        "q11": {h // 4: (h,) for h in model.HEADS}}

dev = model.DEV
S = torch.zeros(joint.WIDE, joint.WIDE, dtype=torch.float64, device=dev)
mean = torch.zeros(joint.WIDE, dtype=torch.float64, device=dev)
Q = {(t, h): torch.zeros(256, 256, dtype=torch.float64, device=dev) for t in ("k7", "k11") for h in (0, 1)}
n = 0
picked, real = draw(), asked()
if len(real) < QUESTIONS:
    real = []
print("%d shards of %d corpora; %s" % (len(picked), len({c for c, _ in picked}),
                                       "%d of the store's questions" % len(real) if real else "questions made of each shard's words"), flush=True)
with torch.no_grad():
    for i, (corpus, path) in enumerate(picked):
        shard = store.read(path)
        ids, cache, spans, tail = model.prefill(shard, raw=True)
        mid, hi = cache.layers[model.MID], cache.layers[model.SCALED]
        cos, sin = model.angles(len(ids))
        x = joint.rows(model.floats(mid, "keys"), model.floats(mid, "values"), model.floats(hi, "keys"), cos, sin)[0].double()
        S += x.T @ x
        mean += x.sum(0)
        n += x.shape[0]
        words = re.findall(r"[A-Za-z]{4,}", shard["text"])
        qs = rnd.sample(real, 12) if real else ["What about " + " ".join(rnd.choice(words) for _ in range(8)) + "?" for _ in range(12)]
        model.scores_each((ids, model.pack(cache), spans, tail), qs)
        for name, tensor in (("q7", "k7"), ("q11", "k11")):
            for h, heads in READ[name].items():
                v = SEEN[name][:, list(heads)].reshape(-1, 256)
                for _ in range(4):
                    at = torch.randint(0, len(ids), (v.shape[0],), device=dev)
                    back = joint.turn(v, cos[at], sin[at], -1.0).double()
                    Q[(tensor, h)] += back.T @ back
        if i % 8 == 0:
            print(i, corpus, len(ids), flush=True)
mean /= n
cov = (S / n - torch.outer(mean, mean)).cpu()
o = model.M.model.layers[model.MID].self_attn.o_proj.weight.float()  # [hidden, 8 heads x 256]
metrics = []
for tensor, h in joint.BLOCKS:
    if tensor == "v7":
        cols = o[:, h * 4 * 256:(h + 1) * 4 * 256].reshape(o.shape[0], 4, 256)
        metrics.append(sum(cols[:, j].T @ cols[:, j] for j in range(4)).double().cpu())
    else:
        metrics.append(Q[(tensor, h)].cpu())
book = joint.make(cov, mean.cpu(), metrics, BITS, rank=int(os.environ.get("RANK", "8")), resid=int(os.environ.get("RESID", "4")))
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
torch.save(book, OUT + ".tmp")
os.replace(OUT + ".tmp", OUT)
json.dump({"bits": BITS, "tokens": n, "shards": [[c, os.path.basename(os.path.dirname(p)) + "/" + os.path.basename(p)] for c, p in picked],
           "questions": "asked" if real else "made", "skip": list(SKIP), "model": model.DIR}, open(OUT + ".json", "w"), indent=1)
print("book at %s: %.2f bits a channel, %d coefficients of %d, %d bytes a token against %d" % (
    OUT, BITS, len(book["widths"]), joint.WIDE, (int(book["widths"].sum()) + 7) // 8, joint.WIDE), flush=True)
