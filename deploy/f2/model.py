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

A question's tail is not run through the stock forward (tail): the tails of
several questions, laid end to end, go through the layers once a shard in
one pass over several shards, each token reading its shard's state in
place, so a shard's keys and values are held once for all the questions
asked of it, nothing of a state is copied for a question or written back,
and no question is padded to another's length.

A state is kept packed (pack) and read unpacked (unpack). With no book
(F2_BOOK, made by fit.py) the two are the same thing: layer 7's keys and
values and layer 11's keys as int8, a byte a channel. With a book the three
are coded together, a few bits a channel (joint.py), and unpacked on the GPU
into that same int8 layout when the state is to be kept there, so a tail
pass reads a kept state the same way either way; a state scored in passing
is read as its decoding made it, in half precision. The scores are always
those of the unpacked state, also for the question that prefills it."""
import bisect, copy, functools, os, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from transformers.models.qwen3_5.modeling_qwen3_5 import apply_rotary_pos_emb
import joint
import store
from names import DIR, BOOK_PATH, BOOK_ID, PLAIN, VERSION

LAYERS = 12  # layers 0..11
SCALED = 11  # the layer whose query scale is doubled
ALONE = 3  # the full-attention layer in which a question's tokens see the question alone
MID = 7  # the full-attention layer whose keys and values a state holds
HEADS = (3, 4)  # heads of layer 11 that are read
CHUNK = 2048  # prefill chunk, in tokens
ANSWER = '{\n  "ids": [\n    "p'  # the reply prefix after the question
DEV = "cuda" if torch.cuda.is_available() else "cpu"
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
if BOOK is not None:
    BOOK = joint.Book(BOOK, DEV)


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


@torch.no_grad()
def unpack(state, kept=True):
    """a state as a tail pass reads it, on the GPU: a state whose keys and
    values are coded together gets them back (a copy; the packed state is
    left as it is), any other is returned as it is. A state to be kept gets
    them as int8, the layout the GPU's tier holds; one scored in passing
    (not kept) gets them as the decoding made them, in half precision, since
    the pass that follows would only turn the int8 back into floats"""
    if not joined(state[1]):
        return state
    c = copy.copy(state[1])
    c.layers = [copy.copy(layer) for layer in state[1].layers]
    mid, top = c.layers[MID], c.layers[SCALED]
    y = BOOK.decode(mid.joint, mid.joint_at, mid.joint_exact)
    k7, v7, k11 = joint.tensors(y, mid.joint_rms.to(y.dtype), *(x.to(y.dtype) for x in angles(y.shape[0])))
    if kept:
        int8(mid, "keys", k7, -2)
        int8(mid, "values", v7, -1)
        int8(top, "keys", k11, -2)
    else:
        mid.keys, mid.values, top.keys = k7[None], v7[None], k11[None]
    for name in ("joint", "joint_at", "joint_exact", "joint_rms"):
        delattr(mid, name)
    made = {id(mid): {"keys", "values", "keys_scale", "values_scale"}, id(top): {"keys", "keys_scale"}}
    for layer in c.layers:
        if isinstance(vars(layer).get("low_left"), dict):
            layer.recurrent_states = dict(layer.recurrent_states)
            for i in layer.low_left:
                layer.recurrent_states[i] = joint.lift(layer.low_left[i], layer.low_right[i], layer.low_rest[i],
                                                       layer.low_scale[i], BOOK.resid).to(torch.bfloat16)
            for name in ("low_left", "low_right", "low_rest", "low_scale"):
                delattr(layer, name)
            made.setdefault(id(layer), set()).add("recurrent_states")
        # what is left of the packed state (the convolution states, a few kB) is copied: a packed state may come
        # as views of one block (f2serve's lift), and a view kept here would keep the whole block on the GPU
        for name, v in list(vars(layer).items()):
            if name in made.get(id(layer), ()):
                continue
            if torch.is_tensor(v):
                setattr(layer, name, v.clone())
            elif isinstance(v, dict):
                setattr(layer, name, {i: t.clone() if torch.is_tensor(t) else t for i, t in v.items()})
    if torch.cuda.is_available():
        # the work above is done before this returns: the caller may now drop the packed state, and a block
        # freed while kernels that read it are still queued on this stream is handed to the next transfer on
        # the lift's stream, which writes over it (seen as scores of noise and out-of-range indices)
        torch.cuda.current_stream().synchronize()
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


@functools.lru_cache(maxsize=64)
@torch.no_grad()
def question_tail(tail, question):
    """the tail's input embeddings on the device and the question's token
    count: every shard of a run shares them, so they are made once. Only the
    question's own tokens are read, and the model is causal, so the tail is
    cut after them: the tokens that follow cannot change those rows"""
    t_ids = tok(tail.replace("QQQ", question) + ANSWER, add_special_tokens=False)["input_ids"]
    nq = tokens(question)
    assert tuple(t_ids[:nq]) == opening(question), "a tail opens with the template and the question"
    return M.model.embed_tokens(torch.tensor([t_ids[:nq]])), nq


def tf32(f):
    """f run with its fp32 products on the tensor cores (TF32: the factors'
    mantissas rounded to 10 bits, the sums kept in fp32), the setting put
    back after. For the delta rule alone: its factors are made from bf16
    activations and states, which hold 8 bits. The readout's sums over the
    attention weights are left in full fp32"""
    @functools.wraps(f)
    def g(*a, **k):
        was = torch.backends.cuda.matmul.allow_tf32
        torch.backends.cuda.matmul.allow_tf32 = True
        try:
            return f(*a, **k)
        finally:
            torch.backends.cuda.matmul.allow_tf32 = was
    return g


@tf32
def delta(query, key, value, decay, beta, state, seen):
    """the gated delta rule's outputs for the questions' tokens, each
    question starting from its shard's recurrent state: what the stock
    chunked rule gives a question's tail run alone as one chunk (it pads a
    tail to 64 tokens, and works out a final state no tail pass keeps).
    query, key, value [shards, heads, tokens, 128], decay and beta [shards,
    heads, tokens], state [shards, heads, 128, 128]; seen [tokens, tokens]
    says, by a token, which tokens come before it or are it: its own
    question's and the opening all share. The rule's one triangular system
    is over all the tokens at once, a token's row holding only the tokens
    it sees, so each question is solved as if alone and the opening once"""
    N, D = key.shape[-2:]
    saw = seen.float()
    query = query * torch.rsqrt((query * query).sum(-1, keepdim=True) + 1e-6) * D ** -0.5
    key = key * torch.rsqrt((key * key).sum(-1, keepdim=True) + 1e-6)
    cum = decay @ saw.T  # each token's decay summed over what it sees, itself included
    grown = cum.exp()[..., None]
    pair = (cum[..., :, None] - cum[..., None, :]).masked_fill(~seen, float("-inf")).exp()
    kt = key.transpose(-1, -2)
    k_beta = key * beta[..., None]
    # what the old state says to the tokens' keys and to their queries
    reads = torch.cat([k_beta * grown, query * grown], -2) @ state
    # each token writes what the state and the tokens before it do not already say of its key
    new = torch.linalg.solve_triangular((k_beta @ kt) * pair, value * beta[..., None] - reads[..., :N, :],
                                        upper=False, unitriangular=True)
    return reads[..., N:, :] + ((query @ kt) * pair) @ new


def linear(net, x, rows, seen, at, back):
    """a linear-attention layer's output for the questions' tokens x
    [shards, tokens, hidden], from the convolution and recurrent states the
    shards' caches hold in rows (one cache layer a shard):
    Qwen3_5GatedDeltaNet.forward with the cache read and not written, over
    tokens that are several questions end to end. A token's convolution
    takes the kernel's width of inputs up to its own in its own question
    (and the opening), the last tokens of the shard before them: for most
    tokens those are the ones before it in the row, and for the tokens at
    (the first of each question after the first) back [those tokens,
    kernel] says which they are"""
    B, N, _ = x.shape
    conv = torch.cat([next(v for v in r.conv_states.values() if torch.is_tensor(v)) for r in rows])
    state = torch.cat([next(v for v in r.recurrent_states.values() if torch.is_tensor(v)) for r in rows]).float()
    w = net.conv1d.weight
    full = torch.cat([conv[..., 1 - w.shape[-1]:].to(w.dtype), net.in_proj_qkv(x).transpose(1, 2).to(w.dtype)], -1)
    mixed = torch.nn.functional.conv1d(full, w, net.conv1d.bias, groups=w.shape[0])
    if len(at):  # a later question's first tokens: the tokens before them in the row are another question's
        again = (full[:, :, back] * w).sum(-1)
        mixed[:, :, at] = again if net.conv1d.bias is None else again + net.conv1d.bias[:, None]
    mixed = torch.nn.functional.silu(mixed).to(x.dtype).transpose(1, 2)
    q, k, v = torch.split(mixed, [net.key_dim, net.key_dim, net.value_dim], dim=-1)
    heads = lambda t, d: t.reshape(B, N, -1, d).transpose(1, 2).float()
    q, k, v = heads(q, net.head_k_dim), heads(k, net.head_k_dim), heads(v, net.head_v_dim)
    rep = net.num_v_heads // net.num_k_heads
    if rep > 1:
        q, k = q.repeat_interleave(rep, dim=1), k.repeat_interleave(rep, dim=1)
    beta = net.in_proj_b(x).sigmoid().transpose(1, 2).float()
    decay = (-net.A_log.float().exp() * torch.nn.functional.softplus(net.in_proj_a(x).float() + net.dt_bias)).transpose(1, 2)
    out = delta(q, k, v, decay, beta, state, seen).transpose(1, 2).to(x.dtype)  # [shards, tokens, heads, 128]
    z = net.in_proj_z(x)
    return net.out_proj(net.norm(out.reshape(-1, net.head_v_dim), z.reshape(-1, net.head_v_dim)).reshape(B, N, -1))


def held(rows, name, top, mine):
    """one bf16 buffer [shards, 2, top + tokens, 256] of what a shard's
    questions read in a layer: the shard's keys or values (int8 times their
    scale, zeros from the shard's end to top; none of them when top is 0,
    layer 3) and after them the questions' own, mine [shards, 2, tokens,
    256]. Each part is written once, where it is read: a shard's numbers
    times their scale go straight into the buffer in its precision, and
    only what lies past a shard's end is filled with zeros"""
    B, G, N, d = mine.shape
    buf = torch.empty((B, G, top + N, d), dtype=torch.bfloat16, device=mine.device)
    for b, r in enumerate(rows if top else ()):
        x, sc = getattr(r, name), vars(r).get(name + "_scale")
        n = x.shape[-2]
        if sc is not None:
            torch.mul(x[0], sc[0].to(buf.dtype), out=buf[b, :, :n])
        else:
            buf[b, :, :n] = x[0]
        buf[b, :, n:top] = 0
    buf[:, :, top:] = mine
    return buf


def weights(q, keys, top, lens, seen, scaling):
    """the attention weights [shards, 2, heads x tokens, top + tokens], in
    fp32, of the questions' queries q [shards, 2, heads of a group, tokens,
    256] over keys (held): a token sees its shard up to the shard's length
    (lens) and, up to itself, its own question's tokens and the opening all
    the questions share (seen [tokens, tokens]: by a token, the tokens it
    sees). A query head reads the keys of its
    group, and a shard's questions and their heads are the rows of one
    product with the shard's keys, which are held once"""
    B, G, each, N, d = q.shape
    w = (q * scaling).reshape(B, G, each * N, d) @ keys.transpose(-1, -2)
    for b, n in enumerate(lens.tolist() if top else ()):
        if n < top:
            w[b, :, :, n:top] = float("-inf")
    w[..., top:].masked_fill_(~seen.repeat(each, 1), float("-inf"))
    return torch.softmax(w, -1, dtype=torch.float32)


@torch.no_grad()
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
    same for every question. seen, a dict, is given the queries of
    layers 7 and 11 as attention used them ("q7", "q11": [shards, 8, tokens,
    256]), which fit.py weighs a book by"""
    B, K = len(states), len(questions)
    tails = [question_tail(states[0][3], q) for q in questions]
    ns = [nq for _, nq in tails]
    same = shared([opening(q) for q in questions])  # the tokens every question opens with are run once: what they come to depends on the shard alone
    # each token's question (-1: the opening all share) and its place in the question's tail
    whose = [-1] * same + [k for k, n in enumerate(ns) for _ in range(same, n)]
    place = list(range(same)) + [t for n in ns for t in range(same, n)]
    who, at = torch.tensor(whose, device=DEV), torch.tensor(place, device=DEV)
    N = len(whose)
    sees = ((who[None] == who[:, None]) | (who[None] < 0)) & (at[None] <= at[:, None])  # by the row's token, of the column's
    # the inputs of each token's convolution: the kernel's width of places up to its own in its question's tail,
    # as places in [the shard's last tokens, the row]: a place before the tail is one of the shard's
    width = next(l.linear_attn.conv1d.weight.shape[-1] for l in M.model.layers if hasattr(l, "linear_attn"))
    first = {k: p for p, k in reversed(list(enumerate(whose)))}  # each question's first own token in the row
    row = lambda k, t: t if t < same else first[k] + t - same
    back = [[width - 1 + row(k, t - d) if t >= d else width - 1 + t - d for d in range(width - 1, -1, -1)]
            for k, t in zip(whose, place)]
    apart = [p for p, b in enumerate(back) if b != list(range(p, p + width))]  # the tokens whose inputs are not the row's before them
    back, apart = torch.tensor([back[p] for p in apart], dtype=torch.long, device=DEV).view(-1, width), torch.tensor(apart, dtype=torch.long, device=DEV)
    h = torch.cat([tails[0][0][0, :same]] + [e[0, same:] for e, _ in tails])[None].expand(B, -1, -1)
    caches = [s[1] for s in states]
    lens = torch.tensor([len(s[0]) for s in states], device=DEV)
    top = max(c.layers[SCALED].keys.shape[-2] for c in caches)
    cos, sin = M.model.rotary_emb(h, (lens[:, None] + at)[None].expand(3, -1, -1))
    for li, layer in enumerate(M.model.layers):
        x = layer.input_layernorm(h)
        rows = [c.layers[li] for c in caches]
        if hasattr(layer, "linear_attn"):
            y = linear(layer.linear_attn, x, rows, sees, apart, back)
        else:
            # Qwen3_5Attention.forward, the shard's keys and values read from its state
            attn = layer.self_attn
            q, gate = torch.chunk(attn.q_proj(x).view(B, N, -1, attn.head_dim * 2), 2, dim=-1)
            q = attn.q_norm(q).transpose(1, 2)
            k = attn.k_norm(attn.k_proj(x).view(B, N, -1, attn.head_dim)).transpose(1, 2)
            q, k = apply_rotary_pos_emb(q, k, cos, sin)
            if seen is not None:
                seen["q%d" % li] = q.float()
            G = k.shape[1]
            q = q.view(B, G, -1, N, attn.head_dim)
            if li == SCALED:
                break
            far = 0 if li == ALONE else top  # layer 3's tokens see their question alone
            w = weights(q, held(rows, "keys", far, k), far, lens, sees, attn.scaling).to(x.dtype)
            y = w @ held(rows, "values", far, attn.v_proj(x).view(B, N, G, -1).transpose(1, 2))
            y = y.view(B, G, -1, N, attn.head_dim).permute(0, 3, 1, 2, 4).reshape(B, N, -1)  # [shards, tokens, heads x 256]
            y = attn.o_proj(y * torch.sigmoid(gate.reshape(B, N, -1)))
        h = h + y
        h = h + layer.mlp(layer.post_attention_layernorm(h))
    # layer 11: only the weights of the heads that are read, one in each group, over the shard's tokens
    each = q.shape[2]
    assert [hd // each for hd in HEADS] == list(range(G)), "one read head in each key-value group"
    q = torch.stack([q[:, g, hd % each] for g, hd in enumerate(HEADS)], 1)[:, :, None]
    w = weights(q, held(rows, "keys", top, k), top, lens, sees, layer.self_attn.scaling)[..., :top]  # [shards, groups, tokens, top]
    # the mean over each question's own tokens but the first two, the heads summed
    share = torch.zeros((K, N), device=DEV)
    for kk, n in enumerate(ns):
        share[kk, ((who == kk) | (who < 0)) & (at >= 2)] = 1.0 / max(n - 2, 1)
    mass = share @ w.sum(1)  # [shards, questions, top]
    cum = torch.nn.functional.pad(mass.cumsum(-1), (1, 0))
    most = max(len(s[2]) for s in states)
    cs, ce = torch.zeros((2, B, most), dtype=torch.long)
    for b, s in enumerate(states):
        sp = torch.tensor(s[2], dtype=torch.long).view(-1, 2)
        cs[b, :len(sp)], ce[b, :len(sp)] = sp[:, 0], sp[:, 1]
    cs, ce = (x.to(DEV)[:, None].expand(B, K, most) for x in (cs, ce))
    out = (cum.gather(2, ce) - cum.gather(2, cs)).cpu()
    return [[out[b, kk, :len(s[2])] for kk in range(K)] for b, s in enumerate(states)]


def scores(state, question):
    """per paragraph: the mean over the question's tokens of the attention
    heads 3 and 4 of layer 11 pay to its line, summed over the two heads"""
    return tail([state], [question])[0][0]
