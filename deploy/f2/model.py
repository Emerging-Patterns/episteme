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

A state is kept packed (pack) and read unpacked (unpack). With no book
(F2_BOOK, made by fit.py) the two are the same thing: layer 7's keys and
values and layer 11's keys as int8, a byte a channel. With a book the three
are coded together, a few bits a channel (joint.py), and unpacked on the GPU
into that same int8 layout, so a tail pass reads a state the same way
either way; the scores are always those of the unpacked state, also for the
question that prefills it."""
import bisect, copy, functools, hashlib, os, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from transformers.cache_utils import DynamicLayer
from transformers.modeling_utils import ALL_ATTENTION_FUNCTIONS
from transformers.models.qwen3_5.modeling_qwen3_5 import apply_rotary_pos_emb
import joint
import store

DIR = os.environ.get("F2_MODEL") or os.environ.get("QWEN_DIR") or store.HOME + "/f2/qwen08"
LAYERS = 12  # layers 0..11
SCALED = 11  # the layer whose query scale is doubled
ALONE = 3  # the full-attention layer in which a question's tokens see the question alone
MID = 7  # the full-attention layer whose keys and values a state holds
HEADS = (3, 4)  # heads of layer 11 that are read
CHUNK = 2048  # prefill chunk, in tokens
ANSWER = '{\n  "ids": [\n    "p'  # the reply prefix after the question
DEV = "cuda" if torch.cuda.is_available() else "cpu"
BOOK_PATH = os.environ.get("F2_BOOK") or store.HOME + "/f2/book.pt"


def read_book(path):
    """the book kept at path and the first twelve hex digits of its file's
    SHA-1, or (None, None) when there is no file"""
    if not os.path.isfile(path) or not os.path.getsize(path):
        return None, None
    return torch.load(path, weights_only=True), hashlib.sha1(open(path, "rb").read()).hexdigest()[:12]


BOOK, BOOK_ID = read_book(BOOK_PATH)
PLAIN = "12|11:2.0|%s|v5" % DIR  # what a state kept with no book depends on
VERSION = PLAIN if BOOK is None else "12|11:2.0|%s|v6|%s" % (DIR, BOOK_ID)  # what a kept state depends on

tok = AutoTokenizer.from_pretrained(DIR)


def grouped(module, query, key, value, attention_mask, scaling, dropout=0.0, **kwargs):
    """the stock eager attention's weights and output, with no copy of a
    key-value head's keys and values for each query head that shares them
    (four here): the query heads of a group are the rows of one product with
    the group's keys, and their weights the rows of one with its values"""
    b, heads, t, d = query.shape
    kv = heads // module.num_key_value_groups
    w = torch.matmul(query.reshape(b, kv, -1, d), key.transpose(2, 3)).view(b, heads, t, -1) * scaling
    if attention_mask is not None:
        w = w + attention_mask
    w = torch.nn.functional.softmax(w, dim=-1, dtype=torch.float32).to(query.dtype)
    out = torch.matmul(w.view(b, kv, -1, w.shape[-1]), value).view(b, heads, t, d)
    return out.transpose(1, 2).contiguous(), w


ALL_ATTENTION_FUNCTIONS.register("grouped", grouped)


def alone(attn, stock, **kwargs):
    """layer 3's attention: as stock while a shard is prefilled; when a tail
    is read (grouped), the tail's tokens attend to the tail alone. The state
    holds no keys of the shard for this layer, so its cache starts empty
    (stack), and of the mask, which has a column for each of the shard's
    tokens and then one for each of the tail's, only the tail's columns
    apply"""
    mask = kwargs.get("attention_mask")
    if attn.config._attn_implementation == "grouped" and mask is not None:
        kwargs["attention_mask"] = mask[..., -kwargs["hidden_states"].shape[-2]:]
    return stock(**kwargs)


class Zero(torch.nn.Module):
    """layer 11's MLP: its output feeds nothing that is read"""

    def forward(self, x):
        return torch.zeros_like(x)


def last(self, hidden_states, position_embeddings, attention_mask, past_key_values=None, **kwargs):
    """layer 11's attention, cut to what scores reads: its keys go to the
    cache with no values, and when a tail is read (grouped) its attention
    weights are those of the stock eager path; the output is zeros, since
    no layer follows and the logits are never read"""
    shape = (*hidden_states.shape[:-1], -1, self.head_dim)
    key = self.k_norm(self.k_proj(hidden_states).view(shape)).transpose(1, 2)
    cos, sin = position_embeddings
    weights = None
    if self.config._attn_implementation != "sdpa":
        q, _gate = torch.chunk(self.q_proj(hidden_states).view(*shape[:-1], self.head_dim * 2), 2, dim=-1)
        q = self.q_norm(q.view(shape)).transpose(1, 2)
        q, key = apply_rotary_pos_emb(q, key, cos, sin)
    else:
        q, key = None, apply_rotary_pos_emb(key, key, cos, sin)[1]
    if past_key_values is not None:
        key = past_key_values.update(key, key[..., :0], self.layer_idx)[0]
    if q is not None:
        b, heads, t, d = q.shape
        kv = heads // self.num_key_value_groups  # as grouped: no copy of the keys per query head
        weights = torch.matmul(q.reshape(b, kv, -1, d), key.transpose(2, 3)).view(b, heads, t, -1) * self.scaling
        if attention_mask is not None:
            weights = weights + attention_mask
        weights = torch.nn.functional.softmax(weights, dim=-1, dtype=torch.float32).to(q.dtype)
    return torch.zeros_like(hidden_states), weights


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
    low = m.model.layers[ALONE].self_attn
    low.forward = functools.partial(alone, low, low.forward)
    full = [i for i, t in enumerate(cfg.layer_types) if t == "full_attention"]
    return m, full.index(SCALED)


M, AT = load()
if BOOK is not None:
    BOOK = joint.Book(BOOK, DEV)


def attention(name):
    for layer in M.model.layers:
        if hasattr(layer, "self_attn"):
            layer.self_attn.config._attn_implementation = name


def template(text):
    """the chat-templated prompt for a shard, split before the question"""
    s = tok.apply_chat_template(store.messages(text, "QQQ"), tokenize=False,
                                add_generation_prompt=True, enable_thinking=False)
    cut = s.rindex("<|im_start|>user\nQuestion: QQQ")
    return s[:cut], s[cut:]


def angles(n):
    """the cosines and sines of the rotary angles at positions 0..n-1"""
    cos, sin = M.model.rotary_emb(torch.zeros(1, device=DEV), torch.arange(n, device=DEV)[None])
    return cos[0].float(), sin[0].float()


def floats(layer, name):
    """a layer's keys or values as floats, whether held as bf16 or as int8
    with a scale: [2 key-value heads, tokens, 256]"""
    x, sc = getattr(layer, name), vars(layer).get(name + "_scale")
    return (x.float() * sc)[0] if sc is not None else x.float()[0]


def int8(layer, name, x, dim):
    """x [2, tokens, 256] put on the layer as int8 with one scale per
    channel over the tokens (dim -2, keys) or per token (dim -1, values:
    KIVI, 2402.02750)"""
    sc = x.abs().amax(dim, keepdim=True).clamp(min=1e-8) / 127
    setattr(layer, name, (x / sc).round().to(torch.int8)[None])
    setattr(layer, name + "_scale", sc[None])


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


@torch.no_grad()
def unpack(state):
    """a state as a tail pass reads it, on the GPU: a state whose keys and
    values are coded together gets them back as int8 (a copy; the packed
    state is left as it is), any other is returned as it is"""
    if not joined(state[1]):
        return state
    c = copy.copy(state[1])
    c.layers = [copy.copy(layer) for layer in state[1].layers]
    mid, top = c.layers[MID], c.layers[SCALED]
    cos, sin = angles(mid.joint.shape[0])
    k7, v7, k11 = joint.tensors(BOOK.decode(mid.joint, mid.joint_at, mid.joint_exact), mid.joint_rms.float(), cos, sin)
    int8(mid, "keys", k7, -2)
    int8(mid, "values", v7, -1)
    int8(top, "keys", k11, -2)
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
    attention("sdpa")
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


@functools.lru_cache(maxsize=8)
@torch.no_grad()
def question_tail(tail, question):
    """the tail's input embeddings on the device and the question's token
    count: every shard of a run shares them, so they are made once. Only the
    question's own tokens are read, and the model is causal, so the tail is
    cut after them: the tokens that follow cannot change those rows"""
    t_ids = tok(tail.replace("QQQ", question) + ANSWER, add_special_tokens=False)["input_ids"]
    nq = len(tok("<|im_start|>user\nQuestion: " + question, add_special_tokens=False)["input_ids"])
    return M.model.embed_tokens(torch.tensor([t_ids[:nq]])), nq


class Roomy(DynamicLayer):
    """a full-attention layer of a stacked cache: its keys and values sit in
    buffers with room after them for the tail's, which update writes there
    (the stock layer appends by copying the whole cache)"""

    def update(self, key_states, value_states, *args, **kwargs):
        end = self.used + key_states.shape[-2]
        self.keys[..., self.used:end, :] = key_states
        self.values[..., self.used:end, :] = value_states
        self.used = end
        return self.keys[..., :end, :], self.values[..., :end, :]

    def get_seq_length(self):
        return self.used


def stack(caches, room):
    """one bf16 cache for several shards' packed caches, the caches left as
    they are: the linear-attention states stacked, the full-attention keys and
    values dequantized into one buffer, right-padded with zeros to the longest
    shard and then by room more tokens for the tail (Roomy); layer 3's buffer
    is the tail's room alone. The layers are fresh objects with fresh tensors,
    so the tail pass touches no shard's own state"""
    out = copy.copy(caches[0])
    out.layers = [copy.copy(layer) for layer in caches[0].layers]
    top = max(c.layers[SCALED].keys.shape[-2] for c in caches)
    for li, layer in enumerate(out.layers):
        rows = [c.layers[li] for c in caches]
        if hasattr(layer, "conv_states"):
            for d in ("conv_states", "recurrent_states"):
                fresh = dict(getattr(layer, d))
                for i, v in fresh.items():
                    if torch.is_tensor(v):
                        fresh[i] = torch.cat([getattr(r, d)[i] for r in rows])
                        if d == "recurrent_states":
                            fresh[i] = fresh[i].float()  # kept in bf16 (pack)
                setattr(layer, d, fresh)
        else:
            layer = out.layers[li] = Roomy()
            held = 0 if li == ALONE else top
            layer.is_initialized, layer.dtype, layer.used = True, torch.bfloat16, held
            for name in ("keys", "values"):
                x0 = getattr(rows[0], name)
                layer.device = x0.device
                buf = torch.zeros((len(rows), *x0.shape[1:-2], held + room, x0.shape[-1]), dtype=torch.bfloat16, device=x0.device)
                for b, r in enumerate(rows):
                    x, sc = getattr(r, name), vars(r).get(name + "_scale")
                    # int8 times its fp32 scale, rounded to bf16 as it is written
                    buf[b, ..., :x.shape[-2], :] = torch.mul(x[0], sc[0]) if sc is not None else x[0]
                setattr(layer, name, buf)
    return out, top


@torch.no_grad()
def scores_batch(states, question):
    """scores(state, question) for several shards in one forward: each
    shard's cache is padded to the longest, the padding masked out, and each
    row's question positions start at its own shard's length"""
    emb, nq = question_tail(states[0][3], question)
    lens = [len(s[0]) for s in states]
    n, t = len(states), emb.shape[1]
    cache, top = stack([s[1] for s in states], t)
    ln = torch.tensor(lens, device=DEV)
    pos = ln[:, None] + torch.arange(t, device=DEV)[None]
    j = torch.arange(top + t, device=DEV)[None, None]
    row = torch.arange(t, device=DEV)[None, :, None]
    ok = (j < ln[:, None, None]) | ((j >= top) & (j - top <= row))
    mask = torch.zeros(ok.shape, dtype=torch.bfloat16, device=DEV).masked_fill(~ok, torch.finfo(torch.bfloat16).min)
    attention("grouped")
    o = M(inputs_embeds=emb.expand(n, -1, -1), past_key_values=cache, position_ids=pos,
          attention_mask={"full_attention": mask[:, None], "linear_attention": None},
          use_cache=True, output_attentions=True, logits_to_keep=1)
    attention("sdpa")
    A = [x for x in o.attentions if x is not None][AT].float()  # shards, heads, tail tokens, keys
    out = []
    for b, (ids, _cache, spans, _tail) in enumerate(states):
        cum = torch.nn.functional.pad(A[b, :, :, :len(ids)].cumsum(-1), (1, 0))
        cs = torch.tensor([s for s, e in spans])
        ce = torch.tensor([e for s, e in spans])
        mass = (cum[:, :, ce] - cum[:, :, cs])[:, 2:nq].mean(1).cpu()
        out.append(mass[HEADS[0]] + mass[HEADS[1]])
    return out


@torch.no_grad()
def scores_each(state, questions):
    """scores(state, q) for several questions over one shard in one forward:
    the shard's cache once a question, each question padded at its end to
    the longest. A question's tokens attend to nothing after them, so the
    padding changes none of its scores"""
    tails = [question_tail(state[3], q) for q in questions]
    n, t = len(tails), max(nq for _, nq in tails)
    emb = tails[0][0].new_zeros((n, t, tails[0][0].shape[-1]))
    for b, (e, nq) in enumerate(tails):
        emb[b, :nq] = e[0]
    ids, _cache, spans, _tail = state
    cache, top = stack([state[1]] * n, t)
    ln = torch.full((n,), len(ids), device=DEV)
    pos = ln[:, None] + torch.arange(t, device=DEV)[None]
    j = torch.arange(top + t, device=DEV)[None, None]
    row = torch.arange(t, device=DEV)[None, :, None]
    ok = (j < ln[:, None, None]) | ((j >= top) & (j - top <= row))
    mask = torch.zeros(ok.shape, dtype=torch.bfloat16, device=DEV).masked_fill(~ok, torch.finfo(torch.bfloat16).min)
    attention("grouped")
    o = M(inputs_embeds=emb, past_key_values=cache, position_ids=pos,
          attention_mask={"full_attention": mask[:, None], "linear_attention": None},
          use_cache=True, output_attentions=True, logits_to_keep=1)
    attention("sdpa")
    A = [x for x in o.attentions if x is not None][AT].float()  # questions, heads, tail tokens, keys
    cs = torch.tensor([s for s, e in spans])
    ce = torch.tensor([e for s, e in spans])
    out = []
    for b, (_e, nq) in enumerate(tails):
        cum = torch.nn.functional.pad(A[b, :, :, :len(ids)].cumsum(-1), (1, 0))
        mass = (cum[:, :, ce] - cum[:, :, cs])[:, 2:nq].mean(1).cpu()
        out.append(mass[HEADS[0]] + mass[HEADS[1]])
    return out


def scores(state, question):
    """per paragraph: the mean over the question's tokens of the attention
    heads 3 and 4 of layer 11 pay to its line, summed over the two heads"""
    return scores_batch([state], question)[0]
