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
from transformers.models.qwen3_5.modeling_qwen3_5 import apply_rotary_pos_emb, repeat_kv
import store

DIR = os.environ.get("F2_MODEL") or os.environ.get("QWEN_DIR") or store.HOME + "/f2/qwen08"
LAYERS = 12  # layers 0..11
SCALED = 11  # the layer whose query scale is doubled
HEADS = (3, 4)  # heads of layer 11 that are read
CHUNK = 2048  # prefill chunk, in tokens
ANSWER = '{\n  "ids": [\n    "p'  # the reply prefix after the question
DEV = "cuda" if torch.cuda.is_available() else "cpu"
VERSION = "12|11:2.0|%s|v3" % DIR  # what a kept state depends on

tok = AutoTokenizer.from_pretrained(DIR)


class Zero(torch.nn.Module):
    """layer 11's MLP: its output feeds nothing that is read"""

    def forward(self, x):
        return torch.zeros_like(x)


def last(self, hidden_states, position_embeddings, attention_mask, past_key_values=None, **kwargs):
    """layer 11's attention, cut to what scores reads: its keys go to the
    cache with no values, and when a tail is read (eager) its attention
    weights are those of the stock eager path; the output is zeros, since
    no layer follows and the logits are never read"""
    shape = (*hidden_states.shape[:-1], -1, self.head_dim)
    key = self.k_norm(self.k_proj(hidden_states).view(shape)).transpose(1, 2)
    cos, sin = position_embeddings
    weights = None
    if self.config._attn_implementation == "eager":
        q, _gate = torch.chunk(self.q_proj(hidden_states).view(*shape[:-1], self.head_dim * 2), 2, dim=-1)
        q = self.q_norm(q.view(shape)).transpose(1, 2)
        q, key = apply_rotary_pos_emb(q, key, cos, sin)
    else:
        q, key = None, apply_rotary_pos_emb(key, key, cos, sin)[1]
    if past_key_values is not None:
        key = past_key_values.update(key, key[..., :0], self.layer_idx)[0]
    if q is not None:
        weights = torch.matmul(q, repeat_kv(key, self.num_key_value_groups).transpose(2, 3)) * self.scaling
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
    channel over the tokens, values with one per token (KIVI, 2402.02750)"""
    for layer in cache.layers:
        for name, dim in (("keys", -2), ("values", -1)):
            x = getattr(layer, name, None)
            if torch.is_tensor(x) and x.dtype == torch.bfloat16 and x.numel():
                sc = x.float().abs().amax(dim, keepdim=True).clamp(min=1e-8) / 127
                setattr(layer, name, (x.float() / sc).round().to(torch.int8))
                setattr(layer, name + "_scale", sc)
    return cache


def unpack(cache):
    """a bf16 copy of a packed cache, for one tail pass"""
    c = copy.deepcopy(cache)
    for layer in c.layers:
        for name in ("keys", "values"):
            sc = vars(layer).pop(name + "_scale", None)
            if sc is not None:
                setattr(layer, name, (getattr(layer, name).float() * sc).to(torch.bfloat16))
    return c


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


@torch.no_grad()
def scores(state, question):
    """per paragraph: the mean over the question's tokens of the attention
    heads 3 and 4 of layer 11 pay to its line, summed over the two heads"""
    ids, cache, spans, tail = state
    emb, nq = question_tail(tail, question)
    attention("eager")
    o = M(inputs_embeds=emb, past_key_values=unpack(cache),
          use_cache=True, output_attentions=True, logits_to_keep=1)
    attention("sdpa")
    A = [x for x in o.attentions if x is not None][AT][0].float()  # heads, tail tokens, all tokens
    cum = torch.nn.functional.pad(A[:, :, :len(ids)].cumsum(-1), (1, 0))
    cs = torch.tensor([s for s, e in spans])
    ce = torch.tensor([e for s, e in spans])
    mass = (cum[:, :, ce] - cum[:, :, cs])[:, 2:nq].mean(1).cpu()  # skip the role tokens
    return mass[HEADS[0]] + mass[HEADS[1]]
