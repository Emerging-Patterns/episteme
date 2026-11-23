"""The attention ranker: Qwen3.5-0.8B cut to layers 0-11, with layer 11's
query scale doubled (its q_norm, stored as 1 + w, becomes 2 (1 + w) - 1).
Layer 11 is the last and only its attention weights are read, so it keeps
no values and computes no output or MLP.

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
and no question is padded to another's length. The pass is f2pass's (tail):
a library of its own kernels in C++ and CUDA (native/f2pass.cu, built into
the environment by this directory's meson.build), which reads the states
where these tensors lie on the device. PyTorch here prefills a shard
(the model's own forward) and holds the memory.

A state is kept packed (pack) and read unpacked (unpack). With no book
(F2_BOOK, made by fit.py) the two are the same thing: layer 7's keys and
values and layer 11's keys as int8, a byte a channel. With a book the three
are coded together, a few bits a channel (joint.py), and unpacked on the GPU
into that same int8 layout when the state is to be kept there, so a tail
pass reads a kept state the same way either way; a state scored in passing
is read as its decoding made it, in half precision. The scores are always
those of the unpacked state, also for the question that prefills it.

The unpacking is f2pass's too, and gives the bits joint.py's own decoding
gives (its arithmetic in the same precision and order)."""
import bisect, copy, ctypes, functools, hashlib, os, sys, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from transformers.models.qwen3_5.modeling_qwen3_5 import apply_rotary_pos_emb
import joint
import store
from names import DIR, BOOK_PATH, BOOK_ID, PLAIN, VERSION

import f2pass

if f2pass.ABI != 2:  # the package in the environment was built from another version of native/
    raise RuntimeError("f2pass in this environment is not this code's: run `uv sync --no-editable` in %s" % os.path.dirname(os.path.abspath(__file__)))

LAYERS = 12  # layers 0..11
SCALED = 11  # the layer whose query scale is doubled
ALONE = 3  # the full-attention layer in which a question's tokens see the question alone
MID = 7  # the full-attention layer whose keys and values a state holds
HEADS = (3, 4)  # heads of layer 11 that are read
CHUNK = 2048  # prefill chunk, in tokens
DEV = "cuda"  # the passes are CUDA kernels: there is no reader on a host alone
# a state kept with a book is coded by it; names.py says what a kept state depends on (VERSION, PLAIN)
BOOK = None if BOOK_ID is None else torch.load(BOOK_PATH, weights_only=True)

tok = AutoTokenizer.from_pretrained(DIR)


class Zero(torch.nn.Module):
    """layer 11's MLP: its output feeds nothing that is read"""

    def forward(self, x):
        return torch.zeros_like(x)


def last(self, hidden_states, position_embeddings, attention_mask, past_key_values=None, **kwargs):
    """layer 11's attention while a shard is prefilled: its keys go to the
    cache with no values, and the output is zeros, since no layer follows
    and the logits are never read (a tail's weights are made by tail)"""
    shape = (*hidden_states.shape[:-1], -1, self.head_dim)
    key = self.k_norm(self.k_proj(hidden_states).view(shape)).transpose(1, 2)
    key = apply_rotary_pos_emb(key, key, *position_embeddings)[1]
    if past_key_values is not None:
        past_key_values.update(key, key[..., :0], self.layer_idx)
    return torch.zeros_like(hidden_states), None


def load():
    """layers 0..11 on the GPU, the embedding table on the CPU, no LM head"""
    m = AutoModelForCausalLM.from_pretrained(DIR, dtype=torch.bfloat16).eval()
    cfg = m.config.text_config if hasattr(m.config, "text_config") else m.config
    m.model.layers = m.model.layers[:LAYERS]
    cfg.layer_types = cfg.layer_types[:LAYERS]
    cfg.num_hidden_layers = LAYERS
    m.lm_head = torch.nn.Identity()
    emb = m.model.embed_tokens
    m.model.embed_tokens = None
    m.to(DEV)
    m.model.embed_tokens = emb
    emb.register_forward_hook(lambda mod, inp, out: out.to(DEV))
    orig = emb.forward
    emb.forward = lambda ids: orig(ids.cpu())
    top = m.model.layers[SCALED]
    top.self_attn.forward = last.__get__(top.self_attn)
    top.mlp = Zero()
    w = top.self_attn.q_norm.weight
    with torch.no_grad():
        w.copy_((1 + w.float()) * 2.0 - 1)
    full = [i for i, t in enumerate(cfg.layer_types) if t == "full_attention"]
    return m, full.index(SCALED)


M, AT = load()
LIB = f2pass.Pass(next(os.path.join(DIR, f) for f in sorted(os.listdir(DIR)) if f.endswith(".safetensors")))  # the weights again, as f2pass lays them
TOKENS = f2pass.TOKENS  # the most tail tokens a pass may hold
if BOOK is not None:
    BOOK = joint.Book(BOOK, DEV)
    # f2pass reads the book's tensors where they lie for as long as the process runs (BOOK holds them)
    if not (BOOK.rank and BOOK.fast == torch.float16 and BOOK.lo.dtype == torch.int64 and BOOK.back.is_contiguous() and LIB.book(
            len(BOOK.step), BOOK.nbytes, *(x.data_ptr() for x in (BOOK.lo, BOOK.shift, BOOK.mask2, BOOK.odd, BOOK.halfstep, BOOK.back, BOOK.mid)),
            BOOK.rank, BOOK.resid)):
        raise RuntimeError("the book at %s is not one f2pass unpacks states of (recurrent states as a rank and four bits)" % BOOK_PATH)


def template(text):
    """the chat-templated prompt for a shard, split before the question"""
    s = tok.apply_chat_template(store.messages(text, "QQQ"), tokenize=False,
                                add_generation_prompt=True, enable_thinking=False)
    cut = s.rindex("<|im_start|>user\nQuestion: QQQ")
    return s[:cut], s[cut:]


ANGLES = [None]  # the cosines and sines made so far, for the longest shard seen


def angles(n):
    """the cosines and sines of the rotary angles at positions 0..n-1"""
    if ANGLES[0] is None or ANGLES[0][0].shape[0] < n:
        cos, sin = M.model.rotary_emb(torch.zeros(1, device=DEV), torch.arange(max(n, 32768), device=DEV)[None])
        ANGLES[0] = (cos[0].float(), sin[0].float())
    return ANGLES[0][0][:n], ANGLES[0][1][:n]


def floats(layer, name):
    """a layer's keys or values as floats, whether held as bf16 or as int8
    with a scale: [2 key-value heads, tokens, 256]"""
    x, sc = getattr(layer, name), vars(layer).get(name + "_scale")
    return (x.float() * sc)[0] if sc is not None else x.float()[0]


def int8(layer, name, x, dim):
    """x [2, tokens, 256] put on the layer as int8 with one scale per
    channel over the tokens (dim -2, keys) or per token (dim -1, values:
    KIVI, 2402.02750)"""
    lo, hi = torch.aminmax(x, dim=dim, keepdim=True)
    sc = torch.maximum(-lo, hi).clamp(min=max(1e-8, torch.finfo(x.dtype).tiny)) / 127
    setattr(layer, name, (x / sc).round().to(torch.int8)[None])
    setattr(layer, name + "_scale", sc.float()[None])


def joined(cache):
    """whether a cache holds its keys and values coded together"""
    return torch.is_tensor(vars(cache.layers[MID]).get("joint"))


def pack(cache):
    """the cache as a state keeps it, in place. Layer 3's keys and values
    are dropped: no tail reads them (alone). The linear-attention recurrent
    states (fp32) are kept in bf16. Layer 7's keys and values and layer 11's
    keys are coded together when there is a book (joint.py): layer 7 then
    holds the tokens' packed rows (joint), the values' root mean squares
    (joint_rms) and the tokens kept exact (joint_at, joint_exact), and no
    keys or values, and each linear-attention layer its recurrent states'
    parts (low_left, low_right, low_rest, low_scale) in place of the
    states; with no book they are int8 and bf16. A cache whose keys and
    values are int8 already (a state kept before the book was made) is
    coded from those"""
    for li, layer in enumerate(cache.layers):
        if li == ALONE:
            layer.keys, layer.values = layer.keys[..., :0, :].clone(), layer.values[..., :0, :].clone()
        states = getattr(layer, "recurrent_states", None)
        if isinstance(states, dict):
            layer.recurrent_states = {i: t.to(torch.bfloat16) if torch.is_tensor(t) and t.dtype == torch.float32 else t
                                      for i, t in states.items()}
            if BOOK is not None and BOOK.rank:
                # each matrix as its first singular triples and the rest in a few bits (joint.low)
                parts = {i: joint.low(t, BOOK.rank, BOOK.resid) for i, t in layer.recurrent_states.items() if torch.is_tensor(t)}
                for at, name in enumerate(("low_left", "low_right", "low_rest", "low_scale")):
                    setattr(layer, name, {i: p[at] for i, p in parts.items()})
                layer.recurrent_states = {i: t[..., :0, :0] if torch.is_tensor(t) else t for i, t in layer.recurrent_states.items()}
    mid, top = cache.layers[MID], cache.layers[SCALED]
    if BOOK is None:
        for layer, name, dim in ((mid, "keys", -2), (mid, "values", -1), (top, "keys", -2)):
            if getattr(layer, name).dtype != torch.int8:
                int8(layer, name, floats(layer, name), dim)
        return cache
    cos, sin = angles(mid.keys.shape[-2])
    x, rms = joint.rows(floats(mid, "keys"), floats(mid, "values"), floats(top, "keys"), cos, sin)
    mid.joint, mid.joint_at, mid.joint_exact = BOOK.encode(x)
    mid.joint_rms = rms.to(torch.float16)
    for layer, name in ((mid, "keys"), (mid, "values"), (top, "keys")):
        setattr(layer, name, getattr(layer, name)[..., :0, :].to(torch.bfloat16))
        vars(layer).pop(name + "_scale", None)
    return cache


def unpacked(cache):
    """the bytes a state's cache takes unpacked to keep (unpack), said from
    the packed cache without unpacking it: what a tier asks before it
    decides whether the state is kept"""
    if not joined(cache):
        return sum(v.numel() * v.element_size() for layer in cache.layers for x in vars(layer).values()
                   for v in (x.values() if isinstance(x, dict) else (x,)) if torch.is_tensor(v))
    size = cache.layers[MID].joint.shape[0] * (joint.WIDE + 8) + 4096  # three int8 tensors, a scale a token, two a channel
    for layer in cache.layers:
        for name, x in vars(layer).items():
            for i, v in (x.items() if isinstance(x, dict) else ((None, x),)):
                if not torch.is_tensor(v) or name.startswith("joint") or name in ("low_right", "low_rest", "low_scale"):
                    continue
                if name == "low_left":  # the matrices it and low_right lift to, in bf16
                    size += v.numel() // v.shape[-1] * layer.low_right[i].shape[-1] * 2
                else:
                    size += v.numel() * v.element_size()
    return size


def again(f):
    """f(), and once more if it fails: f2pass's buffers are its own, not
    PyTorch's, so before the second try what PyTorch holds unused is handed
    back to the device. A second failure is the caller's"""
    try:
        return f()
    except RuntimeError as e:
        print("f2: %s; once more" % e, file=sys.stderr, flush=True)
        torch.cuda.empty_cache()
        return f()


def unpack(state, kept=True):
    """a state as a tail pass reads it, on the GPU: a state whose keys and
    values are coded together gets them back (a copy; the packed state is
    left as it is), any other is returned as it is. A state to be kept gets
    them as int8, the layout the GPU's tier holds; one scored in passing
    (not kept) gets them as the decoding made them, in half precision, since
    the pass that follows would only turn the int8 back into floats.
    PyTorch gives the memory the unpacked state lies in and f2pass fills it"""
    if not joined(state[1]):
        return state
    return again(lambda: unpacking(state, kept))


def spare(layer, made):
    """what is left of a packed state's layer once made's names are set, as
    unpack leaves it: each tensor copied. A packed state may come as views
    of one block (f2serve's lift), and a view kept in the unpacked state
    would keep the whole block on the GPU"""
    for name, v in list(vars(layer).items()):
        if name in made:
            continue
        if torch.is_tensor(v):
            setattr(layer, name, v.clone())
        elif isinstance(v, dict):
            setattr(layer, name, {i: t.clone() if torch.is_tensor(t) else t for i, t in v.items()})


def unpacking(state, kept):
    """unpack's work. ValueError for a packed state whose tensors are not
    what pack leaves"""
    held = []  # what is read only until the library returns

    def whole(x, dtype):
        if x.dtype != dtype:
            raise ValueError("a packed state's %s where pack leaves %s" % (x.dtype, dtype))
        if not x.is_contiguous():  # a part kept as a slice (a state not come through f2serve's lift)
            x = x.contiguous()
            held.append(x)
        return x.data_ptr()

    c = copy.copy(state[1])
    c.layers = [copy.copy(layer) for layer in state[1].layers]
    mid, top = c.layers[MID], c.layers[SCALED]
    T = mid.joint.shape[0]
    cos, sin = angles(T)
    p = f2pass.Packed()
    p.tokens, p.kept, p.exact = T, int(kept), mid.joint_at.shape[0]
    p.joint, p.at, p.rows = whole(mid.joint, torch.uint8), whole(mid.joint_at, torch.int32), whole(mid.joint_exact, torch.float16)
    p.rms, p.cos, p.sin = whole(mid.joint_rms, torch.float16), whole(cos, torch.float32), whole(sin, torch.float32)
    # the linear-attention layers' states: the recurrent ones made, the convolution ones copied, each kind in one block
    lin = [(li, layer) for li, layer in enumerate(c.layers) if isinstance(vars(layer).get("low_left"), dict)]
    if not lin or any(hasattr(layer, "recurrent_states") and not isinstance(vars(layer).get("low_left"), dict) for layer in c.layers):
        raise ValueError("a packed state whose recurrent states are kept whole")
    convs = []
    for li, layer in lin:
        parts = [(i, t) for i, t in layer.low_left.items() if torch.is_tensor(t)]
        cv = [(i, t) for i, t in layer.conv_states.items() if torch.is_tensor(t)]
        if len(parts) != 1 or parts[0][1].shape[-1] != BOOK.rank or len(cv) != 1 or cv[0][1].shape != lin[0][1].conv_states[cv[0][0]].shape:
            raise ValueError("a packed state whose layer %d holds other than one state of the book's rank" % li)
        i, left = parts[0]
        p.left[li], p.right[li] = whole(left, torch.float16), whole(layer.low_right[i], torch.float16)
        p.rest[li], p.scale[li] = whole(layer.low_rest[i], torch.uint8), whole(layer.low_scale[i], torch.float16)
        p.conv[li] = whole(cv[0][1], torch.bfloat16)
        convs.append((i, cv[0][0], cv[0][1].shape))
    rec = torch.empty((len(lin), 1, 16, 128, 128), dtype=torch.bfloat16, device=DEV)
    conv = torch.empty((len(lin),) + tuple(convs[0][2]), dtype=torch.bfloat16, device=DEV)
    p.conv_bytes = conv[0].numel() * 2
    for at, (li, _) in enumerate(lin):
        p.rec[li], p.conv_out[li] = rec[at].data_ptr(), conv[at].data_ptr()
    if kept:
        # int8, a token's two heads side by side as they are in its row
        k7, v7, k11 = (torch.empty((T, 2, 256), dtype=torch.int8, device=DEV) for _ in range(3))
        k7s, k11s = (torch.empty((1, 2, 1, 256), dtype=torch.float32, device=DEV) for _ in range(2))
        v7s = torch.empty((1, 2, T, 1), dtype=torch.float32, device=DEV)
        p.k7, p.v7, p.k11 = k7.data_ptr(), v7.data_ptr(), k11.data_ptr()
        p.k7_scale, p.v7_scale, p.k11_scale = k7s.data_ptr(), v7s.data_ptr(), k11s.data_ptr()
    else:
        y = torch.empty((T, joint.WIDE), dtype=torch.float16, device=DEV)
        p.y = y.data_ptr()
    if torch.cuda.current_stream() != torch.cuda.default_stream():
        torch.cuda.current_stream().synchronize()
    LIB.unpack(p)  # done when it returns: the caller may drop the packed state
    del held
    if kept:
        mid.keys, mid.values, top.keys = (x.transpose(0, 1)[None] for x in (k7, v7, k11))
        mid.keys_scale, mid.values_scale, top.keys_scale = k7s, v7s, k11s
    else:
        mid.keys, mid.values, top.keys = (y[:, at:at + 512].view(-1, 2, 256).transpose(0, 1)[None] for at in (0, 512, 1024))
    for name in ("joint", "joint_at", "joint_exact", "joint_rms"):
        delattr(mid, name)
    made = {id(mid): {"keys", "values", "keys_scale", "values_scale"}, id(top): {"keys", "keys_scale"}}
    for at, (li, layer) in enumerate(lin):
        i, ci, _ = convs[at]
        layer.recurrent_states = {**layer.recurrent_states, i: rec[at]}
        layer.conv_states = {**layer.conv_states, ci: conv[at]}
        for name in ("low_left", "low_right", "low_rest", "low_scale"):
            delattr(layer, name)
        made[id(layer)] = {"recurrent_states", "conv_states"}
    for layer in c.layers:
        spare(layer, made.get(id(layer), ()))
    return (state[0], c) + tuple(state[2:])


@torch.no_grad()
def prefill(shard, raw=False):
    """a shard's state, packed: (prompt ids, cache, paragraph token spans,
    question template); raw leaves the cache as the model made it"""
    head, tail = template(shard["text"])
    enc = tok(head, add_special_tokens=False, return_offsets_mapping=True)
    ids = enc["input_ids"]
    cache = None
    for i in range(0, len(ids), CHUNK):
        out = M(input_ids=torch.tensor([ids[i:i + CHUNK]], device=DEV), past_key_values=cache,
                use_cache=True, logits_to_keep=1)
        cache = out.past_key_values
    starts = [o[0] for o in enc["offset_mapping"]]
    base = head.index(shard["text"].strip())
    spans = []
    for a, b, _ in shard["spans"]:
        ta = bisect.bisect_left(starts, base + a)
        tb = bisect.bisect_left(starts, base + b)
        spans.append((ta, max(tb, ta + 1)))
    return ids, cache if raw else pack(cache), spans, tail


@functools.lru_cache(maxsize=4096)
def opening(question):
    """the tokens of a question's tail a pass runs (question_tail): the
    template's up to the question, then the question's"""
    return tuple(tok("<|im_start|>user\nQuestion: " + question, add_special_tokens=False)["input_ids"])


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
    """what runs the tail passes and the unpacking: f2pass, with the first
    twelve hex digits of its library's SHA-1"""
    return "f2pass " + hashlib.sha1(open(f2pass.LIB._name, "rb").read()).hexdigest()[:12]


def heads(x):
    """a tensor [1, 2, tokens, 256] as f2pass reads it: a pointer a
    key-value head and the bytes from a token's row to the next"""
    size, base = x.element_size(), x.data_ptr()
    return (ctypes.c_void_p * 2)(base, base + x.stride(1) * size), x.stride(2) * size


def lying(state):
    """a state as f2pass reads it where it lies (f2pass.State, and what must
    be held while it is read). ValueError for a state that is not as unpack
    leaves one: its keys and values a kept state's int8 with their scales,
    or the halves of a state scored in passing"""
    ids, cache, spans = state[0], state[1], state[2]
    mid, top = cache.layers[MID], cache.layers[SCALED]
    kind = {torch.int8: f2pass.INT8, torch.float16: f2pass.HALF}.get(mid.keys.dtype)
    held = (mid.keys, mid.values, top.keys)
    if kind is None or any(x.dtype != mid.keys.dtype or x.dim() != 4 or x.shape[-2] != len(ids) or x.stride(3) != 1 for x in held):
        raise ValueError("a state whose keys and values are not as unpack leaves them (%s)" % mid.keys.dtype)
    s = f2pass.State()
    s.len, s.kind = len(ids), kind
    (s.k7, s.k7_step), (s.v7, s.v7_step), (s.k11, s.k11_step) = map(heads, held)
    if kind == f2pass.INT8:
        for name, sc, wide in (("k7_scale", mid.keys_scale, 256), ("v7_scale", mid.values_scale, s.len), ("k11_scale", top.keys_scale, 256)):
            if sc.dtype != torch.float32 or not sc.is_contiguous() or sc.numel() != 2 * wide:
                raise ValueError("a kept state whose %s is not a float a channel or a token" % name)
            setattr(s, name, (ctypes.c_void_p * 2)(sc.data_ptr(), sc.data_ptr() + wide * 4))
    for li, layer in enumerate(cache.layers):
        if hasattr(layer, "conv_states"):
            conv = next(v for v in layer.conv_states.values() if torch.is_tensor(v))
            rec = next(v for v in layer.recurrent_states.values() if torch.is_tensor(v))
            if conv.dtype != torch.bfloat16 or rec.dtype != torch.bfloat16 or not conv.is_contiguous() or not rec.is_contiguous():
                raise ValueError("a state whose layer %d does not hold its states in bf16" % li)
            s.conv[li], s.rec[li], s.conv_len = conv.data_ptr(), rec.data_ptr(), conv.shape[-1]
    flat = (ctypes.c_int * (2 * len(spans)))(*[x for sp in spans for x in sp])
    s.spans, s.span = len(spans), flat
    return s, flat


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
    questions in one pass, [shard][question]. The questions' tails are laid
    end to end, and that row of tokens runs through the layers once a shard,
    each token reading its shard's state where the stock forward would read
    a cache, and of the tokens only those of its own question up to itself.
    A shard's keys and values are held once for all its questions and its
    recurrent states are read, never written, so nothing of a state is
    copied for a question, and a short question beside a long one costs its
    own tokens, not the long one's. The tokens all the questions open with
    (the template's, and the words they share after it) are in the row once:
    a token sees only what comes before it, so what they come to is the
    same for every question. A token's score for a paragraph is the
    attention it pays the paragraph's tokens in the two heads read, summed;
    a question's is the mean over its tokens but the first two. seen, a
    dict, is given the queries of layers 7 and 11 as attention used them
    ("q7": [shards, 8, tokens, 256]; "q11": [shards, 2, tokens, 256], the
    two heads read, in HEADS' order), which fit.py weighs a book by"""
    ids, who, at, same, lens = row(questions)
    there = [lying(s) for s in states]
    most = max(len(s[2]) for s in states)
    # the library's kernels go on the device's default stream, where PyTorch's own are queued unless a thread
    # chose another: what such a thread has queued for these states is waited for first
    if torch.cuda.current_stream() != torch.cuda.default_stream():
        torch.cuda.current_stream().synchronize()
    out = again(lambda: LIB.tail([s for s, _ in there], ids, who, at, same, lens, most))
    if seen is not None:
        for name, wide, q in zip(("q7", "q11"), (8, len(HEADS)), LIB.queries(len(states) * len(ids))):
            seen[name] = torch.frombuffer(q, dtype=torch.bfloat16).view(len(states), len(ids), wide, 256).transpose(1, 2).float().to(DEV)
    res = torch.frombuffer(out, dtype=torch.float32).view(len(states), len(questions), most)
    return [[res[b, k, :len(s[2])].clone() for k in range(len(questions))] for b, s in enumerate(states)]


def scores(state, question):
    """per paragraph: the mean over the question's tokens of the attention
    heads 3 and 4 of layer 11 pay to its line, summed over the two heads"""
    return tail([state], [question])[0][0]
