# Every record `Chat.records(path, project, n, l)` gives has `l`'s ts, source
# `chat:claude/<project>`, `l`'s session as thread and `l`'s parent; its `ptr`
# is empty or `file:<path>:<n>`; and the record each content block makes on
# its own, `Chat.tool` at its index with the `ptr` `file:<path>:<n>`, is among
# them, so no call or result is dropped.
import Base
import ../src/record.bend as R
import ../src/chat.bend as C
import ./defs/ListMembership.bend as D1

# a record's pointer
def rec.ptr(record: R.Record) -> String:
  match record:
    case R.Record{_id, _ts, _source, _author, _thread, _parent, _paras, ptr}:
      ptr

# what every record of a transcript line shares: its ts, source, thread
# and parent
def chat.stamp(record: R.Record) -> String & String & String & String:
  match record:
    case R.Record{_id, ts, source, _author, thread, parent, _paras, _ptr}:
      (ts, source, thread, parent)

# the stamp a line's records carry: the line's ts, the project's source,
# the line's session as thread and its parent
def chat.line.stamp(line: C.Line, project: String) -> String & String & String & String:
  match line:
    case C.Line{_author, _uuid, ts, session, parent, _blocks}:
      (ts, "chat:claude/" ++ project, session, parent)

# LAW: every record of a line carries the line's ts, the project's source,
# the line's session as thread and its parent
law chat_stamp:
  for path: String
  for project: String
  for n: U32
  for line: C.Line
  for r: R.Record
  for h: D1.Elem(R.Record, r, C.Chat.records(path, project, n, line))
  {chat.stamp(r) == chat.line.stamp(line, project)
    : String & String & String & String}

# LAW: a record of a line has no pointer, or points at the line:
# file:<path>:<n>
law chat_ptr:
  for path: String
  for project: String
  for n: U32
  for line: C.Line
  for r: R.Record
  for h: D1.Elem(R.Record, r, C.Chat.records(path, project, n, line))
  Or({rec.ptr(r) == "" : String},
    {rec.ptr(r) == "file:" ++ path ++ ":" ++ U32.show(n) : String})

# the index of the block after the blocks bs, the first at idx
def chat.after(bs: List<&2, C.Block>, idx: U32) -> U32:
  match bs:
    case Nil{}:
      idx
    case Con{_b, rest}:
      chat.after(rest, U32.inc(idx))

# a made record is one of xs; nothing is asked of None
def chat.in(got: Maybe<&2, R.Record>, xs: List<&2, R.Record>) -> Type:
  match got:
    case None{}:
      Unit
    case Some{x}:
      D1.Elem(R.Record, x, xs)

# LAW: the record each block of a line makes on its own (Chat.tool, at its
# index, with the line's pointer file:<path>:<n>) is among the line's
# records, so no call or result is dropped and every result points at
# its line
law chat_blocks:
  for +path: String
  for +project: String
  for +n: U32
  for +author: String
  for +uuid: String
  for +ts: String
  for +session: String
  for +parent: String
  for +pre: List<&2, C.Block>
  for +b: C.Block
  for +post: List<&2, C.Block>
  chat.in(C.Chat.tool(ts, "chat:claude/" ++ project, session, parent,
      "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, chat.after(pre, 0), b),
    C.Chat.records(path, project, n,
      C.Line{author, uuid, ts, session, parent, List.append(&2, C.Block, pre, b <> post)}))
