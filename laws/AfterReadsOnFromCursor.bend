import Base
import ../src/record.bend as R
import ../src/chat.bend as C

# the code points of a text, one byte each: its UTF-8 when it is ASCII
def ascii(text: String) -> List<&2, U32>:
  match text:
    case SNil{}:
      []
    case SCon{c, rest}:
      Char.to_u32(c) <> ascii(rest)

# LAW: an example: a read from an entry's bytes counts on from its lines,
# and an older entry's read from byte 0 skips its lines; the line still
# being written is not counted
law after_example:
  for u: Unit
  {[C.Chat.after(C.At{"f", 3, Some{100}},
        ascii("{\"type\":\"system\"}\n{\"type\":\"system\"}\n{\"ty"), "/r/f", "p"),
      C.Chat.after(C.At{"f", 1, None{}},
        ascii("{\"type\":\"system\"}\n{\"type\":\"system\"}\n{\"ty"), "/r/f", "p")]
    == [(C.At{"f", 5, Some{136}}, []), (C.At{"f", 2, Some{36}}, [])]
    : List<&1, C.At & List<&2, R.Record>>}
