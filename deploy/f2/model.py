"""The attention ranker: Qwen3.5-0.8B cut to layers 0-11, with layer 11's
query scale doubled (its q_norm, stored as 1 + w, becomes 2 (1 + w) - 1).
Layer 11 is the last and only its attention weights are read, so it keeps
no values and computes no output or MLP.

The model is run by f2pass, a library of its own kernels in C++ and CUDA
(native/f2pass.cu, built into the environment by this directory's
meson.build), which reads the weights from the model's safetensors file,
holds the states on the device and packs and unpacks them. This module is
what stands between it and the reader: the tokenizer, the prompt, and a
state's bytes.

A shard's state is the model's cache after the prompt up to the question,
less the keys and values of layer 3: of the three full-attention layers (3,
7 and 11) the question's tokens look back at the shard in layers 7 and 11
only, and in layer 3 at the question alone. What the shard says still
reaches them there through the linear-attention states of the layers
between. A question's score for each paragraph is the attention its tokens
pay to the paragraph's line in heads 3 and 4 of layer 11, averaged over the
question's tokens.

A question's tail is not run through the stock forward: the tails of
several questions, laid end to end, go through the layers once a shard in
one pass over several shards, each token reading its shard's state in
place, so a shard's keys and values are held once for all the questions
asked of it, nothing of a state is copied for a question or written back,
and no question is padded to another's length (tail).

A state is kept packed and read unpacked. Packed it is one run of bytes
(f2pass.h says its layout), the same in a file, in the host's memory and on
its way to the device: its tokens, its paragraphs' spans, the question
template, a score a paragraph for the reader to take from every question's,
and what the state is made of. With no book (F2_BOOK, made by fit.py) that
is layer 7's keys and values and layer 11's keys as int8, a byte a channel;
with a book the three are coded together, a few bits a channel (joint.py).
Unpacked it lies on the device, in the int8 layout when the state is to be
kept there, and for a state of a book that is scored in passing as its
decoding leaves it, in half precision. The scores are always those of the
unpacked state, also for the question that prefills it.
"""
import array, bisect, ctypes, functools, hashlib, os
from tokenizers import Tokenizer
import names
import store
from names import DIR, BOOK_PATH, BOOK_ID, PLAIN, VERSION

import f2pass

if f2pass.ABI != 10:  # the package in the environment was built from another version of native/
    raise RuntimeError("f2pass in this environment is not this code's: run `uv sync --no-editable` in %s" % os.path.dirname(os.path.abspath(__file__)))

LAYERS = 12  # layers 0..11
SCALED = 11  # the layer whose query scale is doubled
ALONE = 3  # the full-attention layer in which a question's tokens see the question alone
MID = 7  # the full-attention layer whose keys and values a state holds
HEADS = (3, 4)  # heads of layer 11 that are read
LINEAR = [li for li in range(LAYERS) if li % 4 != 3]  # the linear-attention layers
TOKENS = f2pass.TOKENS  # the most tail tokens a pass may hold

tok = Tokenizer.from_file(os.path.join(DIR, "tokenizer.json"))
WEIGHTS = next(os.path.join(DIR, f) for f in sorted(os.listdir(DIR)) if f.endswith(".safetensors"))
LIB = f2pass.Pass(WEIGHTS, names.TAIL)  # the weights on the device, and the tail's own when a file of them is given
# a state kept with a book is coded by it; names.py says what a kept state depends on (VERSION, PLAIN)
BOOK = None if BOOK_ID is None else names.book(BOOK_PATH)
if BOOK is not None and not LIB.book(BOOK["coefficients"], *(BOOK[k] for k in ("mean", "fwd", "inv", "widths", "step")), BOOK["exact"],
                                     BOOK["rank"], BOOK["resid"]):
    raise RuntimeError("the book at %s is not one f2pass codes states by (recurrent states as a rank and four bits)" % BOOK_PATH)


def template(text):
    """the prompt for a shard as the model's chat template lays it (ChatML,
    each message's content trimmed, the reply opened with an empty thinking
    block), split before the question"""
    said = ["<|im_start|>%s\n%s<|im_end|>\n" % (m["role"], m["content"].strip()) for m in store.messages(text, "QQQ")]
    return "".join(said[:-1]), said[-1] + "<|im_start|>assistant\n<think>\n\n</think>\n\n"


def pad8(n):
    return (n + 7) & ~7


def told(blob):
    """what a packed state says of itself beside its numbers: its header,
    its prompt's tokens, its paragraphs' token spans, the question template,
    and where the scores the reader keeps in it lie (the first byte): those
    parts come first, each from a multiple of 8 bytes on (f2pass.h)"""
    h = f2pass.head(blob)
    if h.magic != f2pass.MAGIC or len(blob) != f2pass.packed_bytes(h):
        raise ValueError("not a packed state")
    at = ctypes.sizeof(h)
    ids = array.array("i", bytes(blob[at:at + h.tokens * 4]))
    at = pad8(at + h.tokens * 4)
    flat = array.array("i", bytes(blob[at:at + h.spans * 8]))
    at = pad8(at + h.spans * 8)
    tail = bytes(blob[at:at + h.tail]).decode()
    return h, ids, list(zip(flat[::2], flat[1::2])), tail, pad8(at + h.tail)


def null(blob, scores=None):
    """the score a paragraph a packed state holds for the reader to take
    from every question's (floats); given scores, they are written in"""
    h, at = told(blob)[::4]
    if scores is not None:
        blob[at:at + h.null * 4] = array.array("f", scores).tobytes()
    return array.array("f", bytes(blob[at:at + h.null * 4]))


class State:
    """a state unpacked on the device, for as long as this is held: its
    handle there, how many tokens its prompt has, its paragraphs' token
    spans, the question template, and the device bytes it takes"""

    def __init__(self, handle, blob, kept):
        self.handle = handle
        h, self.ids, self.spans, self.tail, _ = told(blob)
        self.size = f2pass.unpacked_bytes(h, kept)

    def __del__(self):
        if LIB is not None:  # gone when the interpreter is on its way out
            LIB.drop(self.handle)


class Sent:
    """a packed state on its way to the device, for as long as this is
    held or until it is taken: its ticket there"""

    def __init__(self, ticket):
        self.ticket = ticket

    def __del__(self):
        if self.ticket is not None and LIB is not None:
            LIB.unstage(self.ticket)


def prefill(shard):
    """a shard's state, packed (bytes that may be written in): its prompt
    up to the question run through the layers and packed by f2pass, with
    its tokens, its paragraphs' token spans and the question template"""
    head, tail = template(shard["text"])
    enc = tok.encode(head, add_special_tokens=False)
    starts = [o[0] for o in enc.offsets]
    base = head.index(shard["text"].strip())
    spans = []
    for a, b, _ in shard["spans"]:
        ta = bisect.bisect_left(starts, base + a)
        tb = bisect.bisect_left(starts, base + b)
        spans.append((ta, max(tb, ta + 1)))
    return LIB.read(enc.ids, spans, tail.encode())


def unpacked(blob, kept=True):
    """the device bytes a packed state takes unpacked, said without
    unpacking it: what a tier asks before it decides whether the state is
    kept"""
    return f2pass.unpacked_bytes(f2pass.head(blob), kept)


def stage(blob):
    """a packed state sent to the device while it works on (Sent): what take needs"""
    return Sent(LIB.stage(blob))


def take(sent, blob, kept=True):
    """a staged state unpacked on the device (State). A state to be kept
    gets the int8 layout the device's tier holds; one scored in passing
    (not kept) is left as its decoding made it, in half precision, since
    the pass that follows would only turn the int8 back into floats"""
    ticket, sent.ticket = sent.ticket, None
    return State(LIB.take(ticket, kept), blob, kept)


def unpack(blob, kept=True):
    """a packed state unpacked on the device (State): stage and take in one"""
    return take(stage(blob), blob, kept)


# ASK_PREFIX: fixed framing before the question text (default "Question: ").
# ASK_PREFIX=auto picks by form: "Question: " if it ends with ?,
# "Find where the record says: " if long, else "Passages about: ".
ASK_PREFIX = os.environ.get("ASK_PREFIX", "Question: ")


def ask_prefix(question):
    if ASK_PREFIX != "auto":
        return ASK_PREFIX
    t = question.strip()
    if t.endswith("?"):
        return "Question: "
    if len(t.split()) > 40:
        return "Find where the record says: "
    return "Passages about: "


@functools.lru_cache(maxsize=4096)
def opening(question):
    """the tokens of a question's tail a pass runs: the template's up to
    the question, then the question's"""
    return tuple(tok.encode("<|im_start|>user\n" + ask_prefix(question) + question, add_special_tokens=False).ids)


def tokens(question):
    """how many tokens of a question's tail a pass runs"""
    return len(opening(question))


def shared(tails):
    """how many tokens several tails (their tokens) all open with, each
    left at least one of its own; none for one tail"""
    same = 0
    while len(tails) > 1 and same < min(map(len, tails)) - 1 and len({ids[same] for ids in tails}) == 1:
        same += 1
    return same


def together(questions):
    """how many tokens a pass runs for these questions: what they all open
    with once, then each one's own (tail)"""
    tails = [opening(q) for q in questions]
    return sum(map(len, tails)) - (len(tails) - 1) * shared(tails)


def by():
    """what runs the model: f2pass, with the first twelve hex digits of its
    library's SHA-1"""
    return "f2pass " + hashlib.sha1(open(f2pass.LIB._name, "rb").read()).hexdigest()[:12]


def row(questions):
    """the row of tail tokens several questions make, as a pass lays it:
    the tokens, each one's question (-1: the opening all share) and its
    place in its question's tail, how many tokens all open with, and each
    question's tail tokens"""
    tails = [opening(q) for q in questions]
    same = shared(tails)
    ids = list(tails[0][:same]) + [t for ids in tails for t in ids[same:]]
    who = [-1] * same + [k for k, ids in enumerate(tails) for _ in ids[same:]]
    at = list(range(same)) + [t for ids in tails for t in range(same, len(ids))]
    return ids, who, at, same, [len(t) for t in tails]


def tail(states, questions, seen=None):
    """scores(state, question) for every one of several shards and several
    questions in one pass, [shard][question], each an array of floats, one
    a paragraph. The questions' tails are laid end to end, and that row of
    tokens runs through the layers once a shard, each token reading its
    shard's state where the stock forward would read a cache, and of the
    tokens only those of its own question up to itself. A shard's keys and
    values are held once for all its questions and its recurrent states are
    read, never written, so nothing of a state is copied for a question,
    and a short question beside a long one costs its own tokens, not the
    long one's. The tokens all the questions open with (the template's, and
    the words they share after it) are in the row once: a token sees only
    what comes before it, so what they come to is the same for every
    question. A token's score for a paragraph is the attention it pays the
    paragraph's tokens in the two heads read, summed; a question's is the
    mean over its tokens but the first two. seen, a dict, is given the
    queries of layers 7 and 11 as attention used them ("q7": bf16 bytes of
    [shards][tokens][8][256]; "q11": of [shards][tokens][2][256], the two
    heads read, in HEADS' order), which fit.py weighs a book by"""
    ids, who, at, same, lens = row(questions)
    most = max(len(s.spans) for s in states)
    out = LIB.tail([s.handle for s in states], ids, who, at, same, lens, most)
    if seen is not None:
        seen["q7"], seen["q11"] = LIB.queries(len(states) * len(ids))
        seen["tokens"] = len(ids)
    flat, K = memoryview(out).cast("B"), len(questions)
    res = []
    for b, s in enumerate(states):
        res.append([])
        for k in range(K):
            a = array.array("f")
            a.frombytes(flat[(b * K + k) * most * 4:((b * K + k) * most + len(s.spans)) * 4])
            res[b].append(a)
    return res


def scores(state, question):
    """per paragraph: the mean over the question's tokens of the attention
    heads 3 and 4 of layer 11 pay to its line, summed over the two heads"""
    return tail([state], [question])[0][0]
