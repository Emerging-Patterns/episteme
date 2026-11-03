# `Chat.tool(.., ptr, author, uuid, i, b)`: for `b` a `Call` whose input has
# at most 4000 code points, the record `claude:<uuid>:<i>` of its name and
# input, by `author`, with no `ptr`; for a longer input, the record whose body
# is `<name>, <size> chars`, by `author`, with `ptr`; for `b` a `Back`, the
# record whose body is `tool result, <size> chars`, by `tool`, with `ptr`.
import Base
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: a tool call whose input JSON has at most 4000 code points is a
# record of its name and input, by the line's author, with no pointer
law call_inline:
  for +ts: String
  for +source: String
  for +thread: String
  for +parent: String
  for +ptr: String
  for +author: String
  for +uuid: String
  for +i: U32
  for name: String
  for +input: String
  for h: {Nat.is_le(String.length(input), 4000n) == True{} : Bool}
  {C.Chat.tool(ts, source, thread, parent, ptr, author, uuid, i, C.Call{name, input})
    == R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
      thread, parent, name ++ "\n" ++ input, "") : Maybe<&2, R.Record>}

# LAW: a tool call whose input JSON is longer is a pointer record, by the
# line's author, its body the name and the input's size in code points,
# pointing at the line
law call_pointer:
  for +ts: String
  for +source: String
  for +thread: String
  for +parent: String
  for +ptr: String
  for +author: String
  for +uuid: String
  for +i: U32
  for name: String
  for +input: String
  for h: {Nat.is_le(String.length(input), 4000n) == False{} : Bool}
  {C.Chat.tool(ts, source, thread, parent, ptr, author, uuid, i, C.Call{name, input})
    == R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
      thread, parent,
      name ++ ", " ++ U32.show(U32.from_nat(String.length(input))) ++ " chars", ptr)
    : Maybe<&2, R.Record>}

# LAW: a tool result is a pointer record by tool, its body the result's
# size, pointing at the line
law back_pointer:
  for ts: String
  for source: String
  for thread: String
  for parent: String
  for ptr: String
  for author: String
  for +uuid: String
  for +i: U32
  for chars: U32
  {C.Chat.tool(ts, source, thread, parent, ptr, author, uuid, i, C.Back{chars})
    == R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, "tool",
      thread, parent, "tool result, " ++ U32.show(chars) ++ " chars", ptr)
    : Maybe<&2, R.Record>}
