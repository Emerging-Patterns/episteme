"""The attention ranker: Qwen3.5-0.8B cut to layers 0-11, with layer 11's
query scale doubled (its q_norm, stored as 1 + w, becomes 2 (1 + w) - 1).

A shard's state is the model's cache after the prompt up to the question.
A question's score for each paragraph is the attention its tokens pay to
the paragraph's line in heads 3 and 4 of layer 11, averaged over the
question's tokens."""
import bisect, copy, os, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
import store

DIR = os.environ.get("F2_MODEL") or os.environ.get("QWEN_DIR") or store.HOME + "/f2/qwen08"
LAYERS = 12  # layers 0..11
SCALED = 11  # the layer whose query scale is doubled
HEADS = (3, 4)  # heads of layer 11 that are read
CHUNK = 2048  # prefill chunk, in tokens
ANSWER = '{\n  "ids": [\n    "p'  # the reply prefix after the question
DEV = "cuda" if torch.cuda.is_available() else "cpu"
VERSION = "12|11:2.0|%s|v1" % DIR  # what a kept state depends on

tok = AutoTokenizer.from_pretrained(DIR)


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
    w = m.model.layers[SCALED].self_attn.q_norm.weight
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
    return ids, cache, spans, tail


@torch.no_grad()
def scores(state, question):
    """per paragraph: the mean over the question's tokens of the attention
    heads 3 and 4 of layer 11 pay to its line, summed over the two heads"""
    ids, cache, spans, tail = state
    t_ids = tok(tail.replace("QQQ", question) + ANSWER, add_special_tokens=False)["input_ids"]
    nq = len(tok("<|im_start|>user\nQuestion: " + question, add_special_tokens=False)["input_ids"])
    attention("eager")
    o = M(input_ids=torch.tensor([t_ids], device=DEV), past_key_values=copy.deepcopy(cache),
          use_cache=True, output_attentions=True, logits_to_keep=1)
    attention("sdpa")
    A = [x for x in o.attentions if x is not None][AT][0].float()  # heads, tail tokens, all tokens
    cum = torch.nn.functional.pad(A[:, :, :len(ids)].cumsum(-1), (1, 0))
    cs = torch.tensor([s for s, e in spans])
    ce = torch.tensor([e for s, e in spans])
    mass = (cum[:, :, ce] - cum[:, :, cs])[:, 2:nq].mean(1).cpu()  # skip the role tokens
    return mass[HEADS[0]] + mass[HEADS[1]]
