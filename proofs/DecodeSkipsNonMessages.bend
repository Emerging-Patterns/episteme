# proofs of laws/DecodeSkipsNonMessages.bend
import Base
import ../src/chat.bend as C
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value
import ../laws/DecodeSkipsNonMessages.bend as Laws

def Laws.decode_compact(js, h):
  %Equal.sym(Maybe<&2, Bool>, Json.as_bool(Json.get(js, "isCompactSummary")),
    Some{True{}}, h)
    : {C.Chat.decode.compact(C.Chat.summary(_), js) == None{} : Maybe<&2, C.Line>}
  {==}

# a line of a type neither user nor assistant is not read, whether or not
# it is a compaction summary
def decode_other.at(
  summary: Bool,
  js: Value.Json,
  -kind: String,
  hk: {Json.as_str(Json.get(js, "type")) == Some{kind} : Maybe<&2, String>},
  hu: {String.eq(kind, "user") == False{} : Bool},
  ha: {String.eq(kind, "assistant") == False{} : Bool},
  ht: {String.eq(kind, "attachment") == False{} : Bool}
) -> {C.Chat.decode.compact(summary, js) == None{} : Maybe<&2, C.Line>}:
  match summary:
    case True{}:
      {==}
    case False{}:
      %Equal.sym(Maybe<&2, String>, Json.as_str(Json.get(js, "type")), Some{kind}, hk)
        : {C.Chat.decode.kind(_, js) == None{} : Maybe<&2, C.Line>}
      %Equal.sym(Bool, String.eq(kind, "user"), False{}, hu)
        : {C.Chat.decode.who(_, String.eq(kind, "assistant"),
          String.eq(kind, "attachment"), js) == None{} : Maybe<&2, C.Line>}
      %Equal.sym(Bool, String.eq(kind, "assistant"), False{}, ha)
        : {C.Chat.decode.who(False{}, _, String.eq(kind, "attachment"), js) == None{}
          : Maybe<&2, C.Line>}
      %Equal.sym(Bool, String.eq(kind, "attachment"), False{}, ht)
        : {C.Chat.decode.who(False{}, False{}, _, js) == None{} : Maybe<&2, C.Line>}
      {==}

def Laws.decode_other(js, kind, hk, hu, ha, ht):
  decode_other.at(C.Chat.summary(Json.as_bool(Json.get(js, "isCompactSummary"))),
    js, kind, hk, hu, ha, ht)

def Laws.block_result(js, h):
  %Equal.sym(Maybe<&2, String>, Json.as_str(Json.get(js, "type")),
    Some{"tool_result"}, h)
    : {C.Chat.block.kind(_, js) == C.Back{C.Chat.size(Json.get(js, "content"))}
      : C.Block}
  {==}
