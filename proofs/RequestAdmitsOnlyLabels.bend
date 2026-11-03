# proofs of laws/RequestAdmitsOnlyLabels.bend
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value
import ../laws/RequestAdmitsOnlyLabels.bend as Laws

# the code's labels are the specification's
law enum_eq:
  for cnt: Nat
  for +idx: U32
  {Rd.Read.enum(cnt, idx) == Laws.label_enum(cnt, idx) : List<&2, Value.Json>}

def enum_eq(cnt, idx):
  match cnt:
    case 0n:
      {==}
    case 1n+more:
      Equal.cong(List<&2, Value.Json>, List<&2, Value.Json>,
        ys => Json.str(S.Shard.label(idx)) <> ys,
        Rd.Read.enum(more, U32.inc(idx)), Laws.label_enum(more, U32.inc(idx)),
        enum_eq(more, U32.inc(idx)))

# the request with the label list xs in the schema's enum
def request_with(slot: U32, +sh: S.Shard, question: String, xs: List<&2, Value.Json>) -> Value.Json:
  +cnt = Laws.shard_paras(sh)
  Json.obj([("messages", Json.arr([Laws.chat_message("system", Laws.reader_prompt()),
      Laws.chat_message("user", S.Shard.render(sh)),
      Laws.chat_message("user", "Question: " ++ question)])),
    ("temperature", Json.num("0")),
    ("max_tokens", Json.num(U32.show(U32.add(U32.mul(6, U32.from_nat(cnt)), 576)))),
    ("cache_prompt", Json.bool(True{})),
    ("id_slot", Json.num(U32.show(slot))),
    ("chat_template_kwargs", Json.obj([("enable_thinking", Json.bool(False{}))])),
    ("response_format", Json.obj([("type", Json.str("json_schema")),
      ("json_schema", Json.obj([("schema", Json.obj([
        ("type", Json.str("object")),
        ("properties", Json.obj([("ids", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("enum", Json.arr(xs))])),
          ("maxItems", Json.num(Nat.show(cnt)))]))])),
        ("required", Json.arr([Json.str("ids")]))]))]))]))])

def Laws.request_body(slot, sh, question):
  Equal.cong(List<&2, Value.Json>, Value.Json,
    xs => request_with(slot, sh, question, xs),
    Rd.Read.enum(Laws.shard_paras(sh), 1), Laws.label_enum(Laws.shard_paras(sh), 1),
    enum_eq(Laws.shard_paras(sh), 1))
