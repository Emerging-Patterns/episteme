# proofs of laws/ChatRecordsKeepEveryBlock.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C
import ../laws/ChatRecordsKeepEveryBlock.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ./lemmas/OrElse.bend as M1

# a record of a made record ahead of rest is the made one, with its stamp,
# or one of rest
def made_stamp(
  -id: String,
  -ts: String,
  -source: String,
  -author: String,
  -thread: String,
  -parent: String,
  ps: List<&2, P.Para>,
  -ptr: String,
  -r: R.Record,
  -rest: List<&2, R.Record>,
  h: D1.Elem(R.Record, r, C.Chat.put(R.Record.make.go(id, ts, source, author, thread, parent, ps, ptr), rest))
) -> Or({Laws.chat.stamp(r) == (ts, source, thread, parent)
  : String & String & String & String}, D1.Elem(R.Record, r, rest)):
  match ps:
    case Nil{}:
      Inr{h}
    case Con{p, more}:
      match h:
        case Inl{e}:
          Inl{%Equal.sym(R.Record, r,
              R.Record{id, ts, source, author, thread, parent, p <> more, ptr}, e)
            : {Laws.chat.stamp(_) == (ts, source, thread, parent)
              : String & String & String & String}
            {==}}
        case Inr{hr}:
          Inr{hr}

# a record is one of a tool call's record ahead of rest
def call_in(
  small: Bool,
  ts: String,
  source: String,
  thread: String,
  parent: String,
  ptr: String,
  author: String,
  uuid: String,
  i: U32,
  name: String,
  input: String,
  r: R.Record,
  rest: List<&2, R.Record>
) -> Type:
  D1.Elem(R.Record, r,
    C.Chat.put(C.Chat.call(small, ts, source, thread, parent, ptr, author, uuid, i, name, input), rest))

# a record of a tool call's record ahead of rest is the call's, with the
# stamp, or one of rest
def call_stamp(
  small: Bool,
  -ts: String,
  -source: String,
  -thread: String,
  -parent: String,
  -ptr: String,
  -author: String,
  -uuid: String,
  -i: U32,
  name: String,
  +input: String,
  -r: R.Record,
  -rest: List<&2, R.Record>,
  h: call_in(small, ts, source, thread, parent, ptr, author, uuid, i, name, input, r, rest)
) -> Or({Laws.chat.stamp(r) == (ts, source, thread, parent)
  : String & String & String & String}, D1.Elem(R.Record, r, rest)):
  match small:
    case True{}:
      made_stamp("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
        thread, parent, P.Para.split(name ++ "\n" ++ input), "", r, rest, h)
    case False{}:
      made_stamp("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
        thread, parent,
        P.Para.split(name ++ ", " ++ U32.show(U32.from_nat(String.length(input))) ++ " chars"),
        ptr, r, rest, h)

# every record a line's blocks make carries the stamp
def tools_stamp(
  bs: List<&2, C.Block>,
  -ts: String,
  -source: String,
  -thread: String,
  -parent: String,
  -ptr: String,
  -author: String,
  -uuid: String,
  -i: U32,
  -r: R.Record,
  h: D1.Elem(R.Record, r, C.Chat.tools(bs, ts, source, thread, parent, ptr, author, uuid, i))
) -> {Laws.chat.stamp(r) == (ts, source, thread, parent)
  : String & String & String & String}:
  match bs:
    case Nil{}:
      Empty.absurd({Laws.chat.stamp(r) == (ts, source, thread, parent)
        : String & String & String & String}, h)
    case Con{b, rest}:
      match b:
        case C.Said{_t}:
          tools_stamp(rest, ts, source, thread, parent, ptr, author, uuid,
            U32.inc(i), r, h)
        case C.Mute{}:
          tools_stamp(rest, ts, source, thread, parent, ptr, author, uuid,
            U32.inc(i), r, h)
        case C.Call{name, +input}:
          M1.or_else({Laws.chat.stamp(r) == (ts, source, thread, parent)
              : String & String & String & String},
            D1.Elem(R.Record, r, C.Chat.tools(rest, ts, source, thread, parent,
              ptr, author, uuid, U32.inc(i))),
            call_stamp(Nat.is_le(String.length(input), C.Chat.inline()), ts, source,
              thread, parent, ptr, author, uuid, i, name, input, r,
              C.Chat.tools(rest, ts, source, thread, parent, ptr, author, uuid,
                U32.inc(i)), h),
            hr => tools_stamp(rest, ts, source, thread, parent, ptr, author, uuid,
              U32.inc(i), r, hr))
        case C.Back{chars}:
          M1.or_else({Laws.chat.stamp(r) == (ts, source, thread, parent)
              : String & String & String & String},
            D1.Elem(R.Record, r, C.Chat.tools(rest, ts, source, thread, parent,
              ptr, author, uuid, U32.inc(i))),
            made_stamp("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source,
              "tool", thread, parent,
              P.Para.split("tool result, " ++ U32.show(chars) ++ " chars"), ptr, r,
              C.Chat.tools(rest, ts, source, thread, parent, ptr, author, uuid,
                U32.inc(i)), h),
            hr => tools_stamp(rest, ts, source, thread, parent, ptr, author, uuid,
              U32.inc(i), r, hr))

def Laws.chat_stamp(path, project, n, line, r, h):
  match line:
    case C.Line{+author, +uuid, +ts, +session, +parent, +blocks}:
      M1.or_else({Laws.chat.stamp(r) == (ts, "chat:claude/" ++ project, session, parent)
          : String & String & String & String},
        D1.Elem(R.Record, r, C.Chat.tools(blocks, ts, "chat:claude/" ++ project,
          session, parent, "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0)),
        made_stamp("claude:" ++ uuid, ts, "chat:claude/" ++ project, author,
          session, parent, P.Para.split(C.Chat.said(blocks)), "", r,
          C.Chat.tools(blocks, ts, "chat:claude/" ++ project, session, parent,
            "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0), h),
        hr => tools_stamp(blocks, ts, "chat:claude/" ++ project, session, parent,
          "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0, r, hr))

# the proof the left or the right gives
def or_case(-A: Type, -B: Type, -C: Type, o: Or(A, B), f: A -> C, g: B -> C) -> C:
  match o:
    case Inl{a}:
      f(a)
    case Inr{b}:
      g(b)

# a record of a made record ahead of rest is the made one, with its
# pointer, or one of rest
def made_ptr(
  -id: String,
  -ts: String,
  -source: String,
  -author: String,
  -thread: String,
  -parent: String,
  ps: List<&2, P.Para>,
  -ptr: String,
  -r: R.Record,
  -rest: List<&2, R.Record>,
  h: D1.Elem(R.Record, r, C.Chat.put(R.Record.make.go(id, ts, source, author, thread, parent, ps, ptr), rest))
) -> Or({Laws.rec.ptr(r) == ptr : String}, D1.Elem(R.Record, r, rest)):
  match ps:
    case Nil{}:
      Inr{h}
    case Con{p, more}:
      match h:
        case Inl{e}:
          Inl{%Equal.sym(R.Record, r,
              R.Record{id, ts, source, author, thread, parent, p <> more, ptr}, e)
            : {Laws.rec.ptr(_) == ptr : String}
            {==}}
        case Inr{hr}:
          Inr{hr}

# the pointer law's claim for a record and a line's pointer
def ptr_claim(r: R.Record, ptr: String) -> Type:
  Or({Laws.rec.ptr(r) == "" : String}, {Laws.rec.ptr(r) == ptr : String})

# "" when none, else the pointer
def if_ptr(none: Bool, ptr: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      ptr

# a made record with no pointer, or the line's, meets the claim
def ptr_made(
  none: Bool,
  -r: R.Record,
  -ptr: String,
  -rest: List<&2, R.Record>,
  o: Or({Laws.rec.ptr(r) == if_ptr(none, ptr) : String}, D1.Elem(R.Record, r, rest)),
  ih: D1.Elem(R.Record, r, rest) -> ptr_claim(r, ptr)
) -> ptr_claim(r, ptr):
  match none:
    case True{}:
      or_case({Laws.rec.ptr(r) == "" : String}, D1.Elem(R.Record, r, rest),
        ptr_claim(r, ptr), o, e => Inl{e}, ih)
    case False{}:
      or_case({Laws.rec.ptr(r) == ptr : String}, D1.Elem(R.Record, r, rest),
        ptr_claim(r, ptr), o, e => Inr{e}, ih)

# a record of a tool call's record ahead of rest has no pointer when the
# input is small, else the line's, or is one of rest
def call_ptr(
  small: Bool,
  -ts: String,
  -source: String,
  -thread: String,
  -parent: String,
  -ptr: String,
  -author: String,
  -uuid: String,
  -i: U32,
  name: String,
  +input: String,
  -r: R.Record,
  -rest: List<&2, R.Record>,
  h: call_in(small, ts, source, thread, parent, ptr, author, uuid, i, name, input, r, rest)
) -> Or({Laws.rec.ptr(r) == if_ptr(small, ptr) : String}, D1.Elem(R.Record, r, rest)):
  match small:
    case True{}:
      made_ptr("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
        thread, parent, P.Para.split(name ++ "\n" ++ input), "", r, rest, h)
    case False{}:
      made_ptr("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
        thread, parent,
        P.Para.split(name ++ ", " ++ U32.show(U32.from_nat(String.length(input))) ++ " chars"),
        ptr, r, rest, h)

# every record a line's blocks make has no pointer, or the line's
def tools_ptr(
  bs: List<&2, C.Block>,
  -ts: String,
  -source: String,
  -thread: String,
  -parent: String,
  -ptr: String,
  -author: String,
  -uuid: String,
  -i: U32,
  -r: R.Record,
  h: D1.Elem(R.Record, r, C.Chat.tools(bs, ts, source, thread, parent, ptr, author, uuid, i))
) -> ptr_claim(r, ptr):
  match bs:
    case Nil{}:
      Empty.absurd(ptr_claim(r, ptr), h)
    case Con{b, rest}:
      match b:
        case C.Said{_t}:
          tools_ptr(rest, ts, source, thread, parent, ptr, author, uuid,
            U32.inc(i), r, h)
        case C.Mute{}:
          tools_ptr(rest, ts, source, thread, parent, ptr, author, uuid,
            U32.inc(i), r, h)
        case C.Call{name, +input}:
          ptr_made(Nat.is_le(String.length(input), C.Chat.inline()), r, ptr,
            C.Chat.tools(rest, ts, source, thread, parent, ptr, author, uuid,
              U32.inc(i)),
            call_ptr(Nat.is_le(String.length(input), C.Chat.inline()), ts, source,
              thread, parent, ptr, author, uuid, i, name, input, r,
              C.Chat.tools(rest, ts, source, thread, parent, ptr, author, uuid,
                U32.inc(i)), h),
            hr => tools_ptr(rest, ts, source, thread, parent, ptr, author, uuid,
              U32.inc(i), r, hr))
        case C.Back{chars}:
          ptr_made(False{}, r, ptr,
            C.Chat.tools(rest, ts, source, thread, parent, ptr, author, uuid,
              U32.inc(i)),
            made_ptr("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source,
              "tool", thread, parent,
              P.Para.split("tool result, " ++ U32.show(chars) ++ " chars"), ptr, r,
              C.Chat.tools(rest, ts, source, thread, parent, ptr, author, uuid,
                U32.inc(i)), h),
            hr => tools_ptr(rest, ts, source, thread, parent, ptr, author, uuid,
              U32.inc(i), r, hr))

def Laws.chat_ptr(path, project, n, line, r, h):
  match line:
    case C.Line{+author, +uuid, +ts, +session, +parent, +blocks}:
      ptr_made(True{}, r, "file:" ++ path ++ ":" ++ U32.show(n),
        C.Chat.tools(blocks, ts, "chat:claude/" ++ project, session, parent,
          "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0),
        made_ptr("claude:" ++ uuid, ts, "chat:claude/" ++ project, author,
          session, parent, P.Para.split(C.Chat.said(blocks)), "", r,
          C.Chat.tools(blocks, ts, "chat:claude/" ++ project, session, parent,
            "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0), h),
        hr => tools_ptr(blocks, ts, "chat:claude/" ++ project, session, parent,
          "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0, r, hr))

# a made record kept in rest is kept with a record ahead of it
def in_cons(
  got: Maybe<&2, R.Record>,
  -y: R.Record,
  -rest: List<&2, R.Record>,
  h: Laws.chat.in(got, rest)
) -> Laws.chat.in(got, y <> rest):
  match got:
    case None{}:
      Unit{}
    case Some{_x}:
      Inr{h}

# a made record kept in rest is kept with another made one ahead of it
def in_keep(
  got: Maybe<&2, R.Record>,
  other: Maybe<&2, R.Record>,
  -rest: List<&2, R.Record>,
  h: Laws.chat.in(got, rest)
) -> Laws.chat.in(got, C.Chat.put(other, rest)):
  match other:
    case None{}:
      h
    case Some{y}:
      in_cons(got, y, rest, h)

# a made record is kept when it is put ahead of rest
def in_here(got: Maybe<&2, R.Record>, -rest: List<&2, R.Record>) -> Laws.chat.in(got, C.Chat.put(got, rest)):
  match got:
    case None{}:
      Unit{}
    case Some{_x}:
      Inl{{==}}

# the record a block after pre makes is among the records of the blocks
def tools_in(
  pre: List<&2, C.Block>,
  +b: C.Block,
  -post: List<&2, C.Block>,
  +ts: String,
  +source: String,
  +thread: String,
  +parent: String,
  +ptr: String,
  +author: String,
  +uuid: String,
  +i: U32
) -> Laws.chat.in(C.Chat.tool(ts, source, thread, parent, ptr, author, uuid, Laws.chat.after(pre, i), b),
  C.Chat.tools(List.append(&2, C.Block, pre, b <> post), ts, source, thread, parent, ptr, author, uuid, i)):
  match pre:
    case Nil{}:
      in_here(C.Chat.tool(ts, source, thread, parent, ptr, author, uuid, i, b),
        C.Chat.tools(post, ts, source, thread, parent, ptr, author, uuid, U32.inc(i)))
    case Con{+x, +rest}:
      in_keep(C.Chat.tool(ts, source, thread, parent, ptr, author, uuid,
          Laws.chat.after(rest, U32.inc(i)), b),
        C.Chat.tool(ts, source, thread, parent, ptr, author, uuid, i, x),
        C.Chat.tools(List.append(&2, C.Block, rest, b <> post), ts, source, thread,
          parent, ptr, author, uuid, U32.inc(i)),
        tools_in(rest, b, post, ts, source, thread, parent, ptr, author, uuid,
          U32.inc(i)))

def Laws.chat_blocks(path, project, n, author, uuid, ts, session, parent, pre, b, post):
  in_keep(C.Chat.tool(ts, "chat:claude/" ++ project, session, parent,
      "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, Laws.chat.after(pre, 0), b),
    R.Record.make("claude:" ++ uuid, ts, "chat:claude/" ++ project, author, session,
      parent, C.Chat.said(List.append(&2, C.Block, pre, b <> post)), ""),
    C.Chat.tools(List.append(&2, C.Block, pre, b <> post), ts, "chat:claude/" ++ project,
      session, parent, "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0),
    tools_in(pre, b, post, ts, "chat:claude/" ++ project, session, parent,
      "file:" ++ path ++ ":" ++ U32.show(n), author, uuid, 0))
