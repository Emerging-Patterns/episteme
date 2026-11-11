"""The attention ranker: Qwen3.5-0.8B cut to layers 0-11, with layer 11's
query scale doubled (its q_norm, stored as 1 + w, becomes 2 (1 + w) - 1).
Layer 11 is the last and only its attention weights are read, so it keeps
no values and computes no output or MLP.

A shard's state is the model's cache after the prompt up to the question.
A question's score for each paragraph is the attention its tokens pay to
the paragraph's line in heads 3 and 4 of layer 11, averaged over the
question's tokens."""
import bisect, copy, functools, os, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from transformers.cache_utils import DynamicLayer
from transformers.modeling_utils import ALL_ATTENTION_FUNCTIONS
from transformers.models.qwen3_5.modeling_qwen3_5 import apply_rotary_pos_emb
import store

DIR = os.environ.get("F2_MODEL") or os.environ.get("QWEN_DIR") or store.HOME + "/f2/qwen08"
LAYERS = 12  # layers 0..11
SCALED = 11  # the layer whose query scale is doubled
HEADS = (3, 4)  # heads of layer 11 that are read
CHUNK = 2048  # prefill chunk, in tokens
ANSWER = '{\n  "ids": [\n    "p'  # the reply prefix after the question
DEV = "cuda" if torch.cuda.is_available() else "cpu"
VERSION = "12|11:2.0|%s|v4" % DIR  # what a kept state depends on

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
    full = [i for i, t in enumerate(cfg.layer_types) if t == "full_attention"]
    return m, full.index(SCALED)


M, AT = load()


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


def pack(cache):
    """the cache's keys and values as int8, in place: keys with one scale per
    channel over the tokens, values with one per token (KIVI, 2402.02750).
    The linear-attention recurrent states (fp32) are kept in bf16"""
    for layer in cache.layers:
        states = getattr(layer, "recurrent_states", None)
        if isinstance(states, dict):
            layer.recurrent_states = {i: t.to(torch.bfloat16) if torch.is_tensor(t) and t.dtype == torch.float32 else t
                                      for i, t in states.items()}
        for name, dim in (("keys", -2), ("values", -1)):
            x = getattr(layer, name, None)
            if torch.is_tensor(x) and x.dtype == torch.bfloat16 and x.numel():
                sc = x.float().abs().amax(dim, keepdim=True).clamp(min=1e-8) / 127
                setattr(layer, name, (x.float() / sc).round().to(torch.int8))
                setattr(layer, name + "_scale", sc)
    return cache


@torch.no_grad()
def prefill(shard):
    """a shard's state: (prompt ids, cache, paragraph token spans, question template)"""
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
    return ids, pack(cache), spans, tail


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
    shard and then by room more tokens for the tail (Roomy). The layers are
    fresh objects with fresh tensors, so the tail pass touches no shard's own
    state"""
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
            layer.is_initialized, layer.dtype, layer.used = True, torch.bfloat16, top
            for name in ("keys", "values"):
                x0 = getattr(rows[0], name)
                layer.device = x0.device
                buf = torch.zeros((len(rows), *x0.shape[1:-2], top + room, x0.shape[-1]), dtype=torch.bfloat16, device=x0.device)
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


def scores(state, question):
    """per paragraph: the mean over the question's tokens of the attention
    heads 3 and 4 of layer 11 pay to its line, summed over the two heads"""
    return scores_batch([state], question)[0]
