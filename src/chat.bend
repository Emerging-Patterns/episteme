# episteme/src/chat: a Claude Code transcript line read as records, the
# complete lines of a transcript file read as UTF-8 from a byte, and the
# connectors' cursors.
# Pure: no IO.
import Base
import ./record.bend as R
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# a content block as ingest keeps it: text or readable thinking (Said), a
# tool call's name and its input as compact JSON (Call), a tool result's
# size in code points and never its text (Back), or anything else (Mute)
type Block is Data:
  Said{text: String}
  Call{name: String, input: String}
  Back{chars: U32}
  Mute{}

# a user or assistant line: its author, uuid, timestamp, session, the
# record id of its parent ("" for none) and its content blocks
type Line is Data:
  Line{author: String, uuid: String, ts: String, session: String,
    parent: String, blocks: List<&2, Block>}

# one entry of the cursor: a transcript file, relative to the root, and how
# many of its complete lines have been read
type Seen is Data:
  Seen{file: String, lines: U32}

# --- a line's records ---

# the record ahead of rest, when there is one
def Chat.put(got: Maybe<&2, R.Record>, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match got:
    case None{}:
      rest
    case Some{rec}:
      rec <> rest

# the said texts of blocks, each followed by a blank line
def Chat.said(bs: List<&2, Block>) -> String:
  match bs:
    case Nil{}:
      ""
    case Con{b, rest}:
      match b:
        case Said{text}:
          text ++ "\n\n" ++ Chat.said(rest)
        case Call{_name, _input}:
          Chat.said(rest)
        case Back{_chars}:
          Chat.said(rest)
        case Mute{}:
          Chat.said(rest)

# the most code points a tool call's input may have and stay inline in its
# record; a bigger one is a pointer to its line
def Chat.inline() -> Nat:
  4000n

# the record of a tool call at index idx of its line, by the line's author:
# its name and input when small, else a pointer to the line whose body is
# the name and the input's size in code points
def Chat.call(
  small: Bool,
  +ts: String,
  +source: String,
  +thread: String,
  +parent: String,
  +ptr: String,
  +author: String,
  +uuid: String,
  +idx: U32,
  name: String,
  +input: String
) -> Maybe<&2, R.Record>:
  match small:
    case True{}:
      R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(idx), ts, source, author,
        thread, parent, name ++ "\n" ++ input, "")
    case False{}:
      R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(idx), ts, source, author,
        thread, parent,
        name ++ ", " ++ U32.show(U32.from_nat(String.length(input))) ++ " chars", ptr)

# the record a block makes on its own, at index idx of its line: a call's
# (Chat.call), or a result's pointer to the line, by "tool"; said and mute
# blocks make none
def Chat.tool(
  +ts: String,
  +source: String,
  +thread: String,
  +parent: String,
  +ptr: String,
  +author: String,
  +uuid: String,
  +idx: U32,
  blk: Block
) -> Maybe<&2, R.Record>:
  match blk:
    case Said{_text}:
      None{}
    case Call{name, +input}:
      Chat.call(Nat.is_le(String.length(input), Chat.inline()), ts, source, thread,
        parent, ptr, author, uuid, idx, name, input)
    case Back{chars}:
      R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(idx), ts, source, "tool",
        thread, parent, "tool result, " ++ U32.show(chars) ++ " chars", ptr)
    case Mute{}:
      None{}

# the records the blocks make on their own, the first at index idx
def Chat.tools(
  bs: List<&2, Block>,
  +ts: String,
  +source: String,
  +thread: String,
  +parent: String,
  +ptr: String,
  +author: String,
  +uuid: String,
  +idx: U32
) -> List<&2, R.Record>:
  match bs:
    case Nil{}:
      []
    case Con{b, rest}:
      Chat.put(Chat.tool(ts, source, thread, parent, ptr, author, uuid, idx, b),
        Chat.tools(rest, ts, source, thread, parent, ptr, author, uuid, U32.inc(idx)))

# the records of a line read from the file at path, line number num, of the
# project: first the said text as claude:<uuid> (none when it has no
# paragraph), then one record per call or result block as
# claude:<uuid>:<block index>, a result's pointing at file:<path>:<num>
def Chat.records(+path: String, +project: String, +num: U32, line: Line) -> List<&2, R.Record>:
  match line:
    case Line{+author, +uuid, +ts, +session, +parent, +blocks}:
      Chat.put(R.Record.make("claude:" ++ uuid, ts, "chat:claude/" ++ project,
        author, session, parent, Chat.said(blocks), ""),
        Chat.tools(blocks, ts, "chat:claude/" ++ project, session, parent,
          "file:" ++ path ++ ":" ++ U32.show(num), author, uuid, 0))

# --- reading a line's JSON ---

# a string, or "" when there is none
def Chat.text(got: Maybe<&2, String>) -> String:
  Maybe.default(&2, String, got, "")

# the code points of the text of each item, those that have one
def Chat.texts(js: List<&2, Value.Json>) -> Nat:
  match js:
    case Nil{}:
      0n
    case Con{head, rest}:
      Nat.add(String.length(Chat.text(Json.as_str(Json.get(head, "text")))),
        Chat.texts(rest))

# a tool result's size: its text's code points, or the sum of its items'
# text code points
def Chat.size.of(got: Maybe<&2, String>, js: Value.Json) -> U32:
  match got:
    case Some{text}:
      U32.from_nat(String.length(text))
    case None{}:
      U32.from_nat(Chat.texts(Json.items(js)))

# the size of a tool result's content
def Chat.size(+js: Value.Json) -> U32:
  Chat.size.of(Json.as_str(js), js)

# a block of the kind its type names
def Chat.block.of(said: Bool, think: Bool, call: Bool, back: Bool, +js: Value.Json) -> Block:
  match said think call back:
    case True{} _ _ _:
      Said{Chat.text(Json.as_str(Json.get(js, "text")))}
    case False{} True{} _ _:
      Said{Chat.text(Json.as_str(Json.get(js, "thinking")))}
    case False{} False{} True{} _:
      Call{Chat.text(Json.as_str(Json.get(js, "name"))),
        Json.print(Json.get(js, "input"))}
    case False{} False{} False{} True{}:
      Back{Chat.size(Json.get(js, "content"))}
    case False{} False{} False{} False{}:
      Mute{}

# a block of its type: text, thinking, tool_use, tool_result, else mute
def Chat.block.kind(got: Maybe<&2, String>, +js: Value.Json) -> Block:
  match got:
    case None{}:
      Mute{}
    case Some{+kind}:
      Chat.block.of(String.eq(kind, "text"), String.eq(kind, "thinking"),
        String.eq(kind, "tool_use"), String.eq(kind, "tool_result"), js)

# a content block read from its JSON object
def Chat.block(+js: Value.Json) -> Block:
  Chat.block.kind(Json.as_str(Json.get(js, "type")), js)

# content blocks read from JSON objects, in order
def Chat.blocks(js: List<&2, Value.Json>) -> List<&2, Block>:
  match js:
    case Nil{}:
      []
    case Con{head, rest}:
      Chat.block(head) <> Chat.blocks(rest)

# a message's content: a string is one said block, else its array's blocks
def Chat.content.of(got: Maybe<&2, String>, js: Value.Json) -> List<&2, Block>:
  match got:
    case Some{text}:
      [Said{text}]
    case None{}:
      Chat.blocks(Json.items(js))

# the blocks of a message's content
def Chat.content(+js: Value.Json) -> List<&2, Block>:
  Chat.content.of(Json.as_str(js), js)

# a parent uuid as a record id, or "" for none
def Chat.parent(got: Maybe<&2, String>) -> String:
  match got:
    case None{}:
      ""
    case Some{uuid}:
      "claude:" ++ uuid

# the line of the parts read, or None when uuid or timestamp is missing
def Chat.line.of(
  author: String,
  uuid: Maybe<&2, String>,
  ts: Maybe<&2, String>,
  session: String,
  parent: String,
  blocks: List<&2, Block>
) -> Maybe<&2, Line>:
  match uuid ts:
    case Some{u} Some{t}:
      Some{Line{author, u, t, session, parent, blocks}}
    case _ _:
      None{}

# the line of a JSON object's uuid, timestamp, session and parent, with
# the author and blocks given
def Chat.line.with(author: String, blocks: List<&2, Block>, +js: Value.Json) -> Maybe<&2, Line>:
  Chat.line.of(author, R.Record.full(js, "uuid"),
    R.Record.full(js, "timestamp"), Chat.text(Json.as_str(Json.get(js, "sessionId"))),
    Chat.parent(R.Record.full(js, "parentUuid")), blocks)

# a user or assistant line by the author, read from its JSON object
def Chat.line(author: String, +js: Value.Json) -> Maybe<&2, Line>:
  Chat.line.with(author, Chat.content(Json.get(Json.get(js, "message"), "content")), js)

# a boolean field of an object, False when it is missing
def Chat.flag(+js: Value.Json, key: String) -> Bool:
  Maybe.default(&2, Bool, Json.as_bool(Json.get(js, key)), False{})

# the kind of an object's origin, "" when it has none
def Chat.origin(+js: Value.Json) -> String:
  Chat.text(Json.as_str(Json.get(Json.get(js, "origin"), "kind")))

# who wrote a user line of a main transcript: noah when its origin is a
# human (or it has none), else meta for a meta line, else the origin's kind
def Chat.human.of(plain: Bool, meta: Bool, kind: String) -> String:
  match plain meta:
    case True{} False{}:
      "noah"
    case True{} True{}:
      "meta"
    case False{} _:
      kind

# who wrote a user line: agent in a subagent (sidechain) transcript, else
# as Chat.human.of says from isMeta and the origin's kind
def Chat.human(side: Bool, meta: Bool, +kind: String) -> String:
  match side:
    case True{}:
      "agent"
    case False{}:
      Chat.human.of(Bool.or(String.eq(kind, ""), String.eq(kind, "human")), meta, kind)

# True when a string read is the one wanted
def Chat.is(got: Maybe<&2, String>, +want: String) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{text}:
      String.eq(text, want)

# who a queued prompt is by: noah for a human's, channel for a channel's;
# others (task notifications, with or without an origin) are not read
def Chat.queued.who.of(human: Bool, channel: Bool) -> Maybe<&2, String>:
  match human channel:
    case True{} _:
      Some{"noah"}
    case False{} True{}:
      Some{"channel"}
    case False{} False{}:
      None{}

# who a queued prompt of the origin's kind is by, or None
def Chat.queued.who(+kind: String) -> Maybe<&2, String>:
  Chat.queued.who.of(String.eq(kind, "human"), String.eq(kind, "channel"))

# a queued prompt's line by the author, its prompt the body, or None
def Chat.queued.by(got: Maybe<&2, String>, +att: Value.Json, +js: Value.Json) -> Maybe<&2, Line>:
  match got:
    case None{}:
      None{}
    case Some{author}:
      Chat.line.with(author, Chat.content(Json.get(att, "prompt")), js)

# a queued prompt's line, or None for any other attachment
def Chat.queued.if(queued: Bool, +att: Value.Json, +js: Value.Json) -> Maybe<&2, Line>:
  match queued:
    case True{}:
      Chat.queued.by(Chat.queued.who(Chat.origin(att)), att, js)
    case False{}:
      None{}

# an attachment line: a prompt queued while Claude was busy
# (attachment.type queued_command) by a human or a channel is read, its
# attachment.prompt the body; any other is not
def Chat.queued(+js: Value.Json) -> Maybe<&2, Line>:
  +att = Json.get(js, "attachment")
  Chat.queued.if(Chat.is(Json.as_str(Json.get(att, "type")), "queued_command"), att, js)

# a line of the kind: user, assistant and attachment lines are read,
# others are not
def Chat.decode.who(user: Bool, assistant: Bool, attach: Bool, +js: Value.Json) -> Maybe<&2, Line>:
  match user assistant attach:
    case True{} _ _:
      Chat.line(Chat.human(Chat.flag(js, "isSidechain"), Chat.flag(js, "isMeta"),
        Chat.origin(js)), js)
    case False{} True{} _:
      Chat.line(Chat.text(Json.as_str(Json.get(Json.get(js, "message"), "model"))), js)
    case False{} False{} True{}:
      Chat.queued(js)
    case False{} False{} False{}:
      None{}

# a line of its type
def Chat.decode.kind(got: Maybe<&2, String>, +js: Value.Json) -> Maybe<&2, Line>:
  match got:
    case None{}:
      None{}
    case Some{+kind}:
      Chat.decode.who(String.eq(kind, "user"), String.eq(kind, "assistant"),
        String.eq(kind, "attachment"), js)

# a line unless it is a compaction summary
def Chat.decode.compact(summary: Bool, +js: Value.Json) -> Maybe<&2, Line>:
  match summary:
    case True{}:
      None{}
    case False{}:
      Chat.decode.kind(Json.as_str(Json.get(js, "type")), js)

# True when a line says it is a compaction summary
def Chat.summary(got: Maybe<&2, Bool>) -> Bool:
  Maybe.default(&2, Bool, got, False{})

# a transcript line read from its JSON object: None for a compaction
# summary (isCompactSummary true), a type other than user, assistant or
# attachment, an attachment other than a human's or channel's queued
# prompt, or a missing uuid or timestamp
def Chat.decode(+js: Value.Json) -> Maybe<&2, Line>:
  Chat.decode.compact(Chat.summary(Json.as_bool(Json.get(js, "isCompactSummary"))), js)

# the line's records, or none
def Chat.of(+path: String, +project: String, +num: U32, got: Maybe<&2, Line>) -> List<&2, R.Record>:
  match got:
    case None{}:
      []
    case Some{line}:
      Chat.records(path, project, num, line)

# the records of a parsed line, or none
def Chat.parsed(+path: String, +project: String, +num: U32, got: Maybe<&2, Value.Json>) -> List<&2, R.Record>:
  match got:
    case None{}:
      []
    case Some{+js}:
      Chat.of(path, project, num, Chat.decode(js))

# True when a, else what the rest says
def Chat.keep.if(found: Bool, rest: Unit -> Bool) -> Bool:
  match found:
    case True{}:
      True{}
    case False{}:
      rest(Unit{})

# True when a line may make a record: it holds `"type":"user"`,
# `"type":"assistant"` or `queued_command` as Claude Code writes them. A
# line Chat.decode reads holds one of them, so a line that holds none is
# not parsed
def Chat.keep(+text: String) -> Bool:
  Chat.keep.if(String.contains(text, "\"type\":\"user\""),
    _u => Chat.keep.if(String.contains(text, "\"type\":\"assistant\""),
      _v => String.contains(text, "queued_command")))

# the records of a line Chat.keep keeps, else none
def Chat.read.if(keep: Bool, +path: String, +project: String, +num: U32, text: String) -> List<&2, R.Record>:
  match keep:
    case True{}:
      Chat.parsed(path, project, num, Json.parse(text))
    case False{}:
      []

# the records of the text of line n of the transcript at path: none when
# Chat.keep drops it, it is not JSON or Chat.decode gives no line
def Chat.read(+path: String, +project: String, +num: U32, +text: String) -> List<&2, R.Record>:
  Chat.read.if(Chat.keep(text), path, project, num, text)

# the records of the lines, numbered from n, in order
def Chat.file(lines: List<&2, String>, +path: String, +project: String, +num: U32) -> List<&2, R.Record>:
  match lines:
    case Nil{}:
      []
    case Con{text, rest}:
      List.append(&2, R.Record, Chat.read(path, project, num, text),
        Chat.file(rest, path, project, U32.inc(num)))

# the tail when the head is the dash, else the whole name
def Chat.project.if(dash: Bool, head: Char, tail: String) -> String:
  match dash:
    case True{}:
      tail
    case False{}:
      SCon{head, tail}

# a project directory's name without its leading "-": -home-noah-x is
# home-noah-x
def Chat.project(dir: String) -> String:
  match dir:
    case SNil{}:
      ""
    case SCon{+head, tail}:
      Chat.project.if(Char.is_eq(head, '-'), head, tail)

# --- complete lines ---

# the line read so far, reversed, after one more character: empty after a
# line feed
def Chat.lines.cur(feed: Bool, head: Char, cur: String) -> String:
  match feed:
    case True{}:
      ""
    case False{}:
      SCon{head, cur}

# the lines read so far, reversed, after one more character: a line feed
# ends the line read so far
def Chat.lines.acc(feed: Bool, cur: String, acc: List<&2, String>) -> List<&2, String>:
  match feed:
    case True{}:
      String.reverse(cur) <> acc
    case False{}:
      acc

# the complete lines of text after those in acc (reversed); a loop, so a
# file of any size is read without a deep stack
def Chat.lines.go(text: String, +cur: String, acc: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}:
      List.reverse(&2, String, acc)
    case SCon{+head, tail}:
      +feed = Char.is_eq(head, '\n')
      Chat.lines.go(tail, Chat.lines.cur(feed, head, cur),
        Chat.lines.acc(feed, cur, acc))

# the complete lines of a text, each without its line feed: the text after
# the last line feed is a line still being written and is not one
def Chat.lines(text: String) -> List<&2, String>:
  Chat.lines.go(text, "", [])

# the lines after the first num
def Chat.skip(num: Nat, lines: List<&2, String>) -> List<&2, String>:
  match num lines:
    case 0n _:
      lines
    case 1n+k Con{_head, rest}:
      Chat.skip(k, rest)
    case 1n+_k Nil{}:
      []

# --- UTF-8 ---

# True for a continuation byte, 0x80 to 0xBF
def Chat.utf8.cont(+byte: U32) -> Bool:
  U32.is_eq(U32.and(byte, 192), 128)

# the tail read on when the byte was a continuation byte, else None
def Chat.utf8.tail.if(ok: Bool, rest: Unit -> Maybe<&1, U32 & List<&2, U32>>) -> Maybe<&1, U32 & List<&2, U32>>:
  match ok:
    case True{}:
      rest(Unit{})
    case False{}:
      None{}

# the code point after more continuation bytes of bs, cp the bits so
# far, and the bytes after them; None when one is missing or is no
# continuation byte
def Chat.utf8.tail(more: Nat, +cp: U32, bs: List<&2, U32>) -> Maybe<&1, U32 & List<&2, U32>>:
  match more:
    case 0n:
      Some{(cp, bs)}
    case 1n+k:
      match bs:
        case Nil{}:
          None{}
        case Con{+byte, rest}:
          Chat.utf8.tail.if(Chat.utf8.cont(byte),
            _u => Chat.utf8.tail(k, U32.or(U32.shln(cp, 6n), U32.and(byte, 63)), rest))

# a lead byte's continuation bytes and its bits: 0x00 to 0x7F has none,
# 0xC2 to 0xDF one, 0xE0 to 0xEF two, 0xF0 to 0xF4 three; any other byte
# is no lead (None)
def Chat.utf8.lead(+byte: U32) -> Maybe<&1, Nat & U32>:
  Bool.pick(Maybe<&1, Nat & U32>, U32.is_lt(byte, 128), Some{(0n, byte)},
    Bool.pick(Maybe<&1, Nat & U32>, U32.is_lt(byte, 194), None{},
      Bool.pick(Maybe<&1, Nat & U32>, U32.is_lt(byte, 224), Some{(1n, U32.and(byte, 31))},
        Bool.pick(Maybe<&1, Nat & U32>, U32.is_lt(byte, 240), Some{(2n, U32.and(byte, 15))},
          Bool.pick(Maybe<&1, Nat & U32>, U32.is_lt(byte, 245), Some{(3n, U32.and(byte, 7))},
            None{})))))

# the least code point a sequence of more continuation bytes may encode
def Chat.utf8.least(more: Nat) -> U32:
  match more:
    case 0n:
      0
    case 1n:
      128
    case 2n:
      2048
    case 3n+_k:
      65536

# a decoded code point, or U+FFFD when it is overlong, a surrogate or past
# U+10FFFF
def Chat.utf8.check(+more: Nat, +cp: U32) -> U32:
  Bool.pick(U32,
    Bool.and(U32.is_ge(cp, Chat.utf8.least(more)),
      Bool.and(Bool.or(U32.is_lt(cp, 55296), U32.is_gt(cp, 57343)),
        U32.is_lt(cp, 1114112))),
    cp, 65533)

# a sequence's code point, U+FFFD when it is cut short or broken
def Chat.utf8.seq.code(+more: Nat, got: Maybe<&1, U32 & List<&2, U32>>) -> U32:
  match got:
    case None{}:
      65533
    case Some{(+cp, _after)}:
      Chat.utf8.check(more, cp)

# the bytes after a sequence, or rest, the bytes after its lead, when it
# is cut short or broken
def Chat.utf8.seq.rest(got: Maybe<&1, U32 & List<&2, U32>>, rest: List<&2, U32>) -> List<&2, U32>:
  match got:
    case None{}:
      rest
    case Some{(_cp, after)}:
      after

# the code point of a lead and the bytes after it; U+FFFD for a byte that
# is no lead
def Chat.utf8.code(got: Maybe<&1, Nat & U32>, rest: List<&2, U32>) -> U32:
  match got:
    case None{}:
      65533
    case Some{(+n, bits)}:
      Chat.utf8.seq.code(n, Chat.utf8.tail(n, bits, rest))

# the bytes after a lead's sequence; rest for a byte that is no lead
def Chat.utf8.next(got: Maybe<&1, Nat & U32>, +rest: List<&2, U32>) -> List<&2, U32>:
  match got:
    case None{}:
      rest
    case Some{(+n, bits)}:
      Chat.utf8.seq.rest(Chat.utf8.tail(n, bits, rest), rest)

# the code points of bs after those in acc (reversed), fuel at least the
# bytes left, as each step reads one or more; a loop, so a file of any
# size is read without a deep stack
def Chat.utf8.go(fuel: Nat, bs: List<&2, U32>, acc: String) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n+f:
      match bs:
        case Nil{}:
          String.reverse(acc)
        case Con{+b, +rest}:
          Chat.utf8.go(f, Chat.utf8.next(Chat.utf8.lead(b), rest),
            SCon{Chr{Chat.utf8.code(Chat.utf8.lead(b), rest)}, acc})

# bytes read as UTF-8: a broken or cut-short sequence is one U+FFFD and
# reading goes on at the byte after its lead. A continuation byte is
# never a line feed, so each line feed byte is one line feed, and no
# other byte gives one
def Chat.utf8(+bs: List<&2, U32>) -> String:
  Chat.utf8.go(List.length(&2, U32, bs), bs, "")

# --- the cursor ---

# "" at a tab, else head and the rest up to the tab
def Chat.upto.tab.if(tab: Bool, head: Char, rest: Unit -> String) -> String:
  match tab:
    case True{}:
      ""
    case False{}:
      SCon{head, rest(Unit{})}

# the text up to its first tab, or the whole text
def Chat.upto.tab(text: String) -> String:
  match text:
    case SNil{}:
      ""
    case SCon{+head, tail}:
      Chat.upto.tab.if(Char.is_eq(head, '\t'), head, _u => Chat.upto.tab(tail))

# the text after this tab, else after the next one
def Chat.after.tab.if(tab: Bool, tail: String, rest: Unit -> String) -> String:
  match tab:
    case True{}:
      tail
    case False{}:
      rest(Unit{})

# the text after its first tab, or "" when it has none
def Chat.after.tab(text: String) -> String:
  match text:
    case SNil{}:
      ""
    case SCon{+head, +tail}:
      Chat.after.tab.if(Char.is_eq(head, '\t'), tail, _u => Chat.after.tab(tail))

# a cursor entry of a file and its number, or None when it has none
def Chat.seen.of(file: String, got: Maybe<&2, U32>) -> Maybe<&2, Seen>:
  match got:
    case None{}:
      None{}
    case Some{num}:
      Some{Seen{file, num}}

# a cursor entry from its line "<lines>\t<file>", or None when it is not one
def Chat.seen.line(+text: String) -> Maybe<&2, Seen>:
  Chat.seen.of(Chat.after.tab(text), U32.read(Chat.upto.tab(text)))

# the entry ahead of rest, when there is one
def Chat.seen.put(got: Maybe<&2, Seen>, rest: List<&2, Seen>) -> List<&2, Seen>:
  match got:
    case None{}:
      rest
    case Some{s}:
      s <> rest

# cursor entries from its lines
def Chat.seen.lines(lines: List<&2, String>) -> List<&2, Seen>:
  match lines:
    case Nil{}:
      []
    case Con{+text, rest}:
      Chat.seen.put(Chat.seen.line(text), Chat.seen.lines(rest))

# the cursor's entries, one "<lines>\t<file>" line each; a line that is
# not one is dropped
def Chat.cursor(text: String) -> List<&2, Seen>:
  Chat.seen.lines(String.lines(text))

# num when hit, else what the rest says
def Chat.cursor.get.if(hit: Bool, num: U32, rest: Unit -> U32) -> U32:
  match hit:
    case True{}:
      num
    case False{}:
      rest(Unit{})

# the lines of a file the cursor has read, 0 when it lists none
def Chat.cursor.get(seen: List<&2, Seen>, +file: String) -> U32:
  match seen:
    case Nil{}:
      0
    case Con{s, rest}:
      match s:
        case Seen{name, num}:
          Chat.cursor.get.if(String.eq(name, file), num,
            _u => Chat.cursor.get(rest, file))

# the entry with the new number when hit, ahead of the rest set
def Chat.cursor.set.if(
  hit: Bool,
  name: String,
  old: U32,
  +num: U32,
  rest: List<&2, Seen>,
  more: Unit -> List<&2, Seen>
) -> List<&2, Seen>:
  match hit:
    case True{}:
      Seen{name, num} <> rest
    case False{}:
      Seen{name, old} <> more(Unit{})

# the cursor with the file's lines set: its entry replaced in place, or a
# new entry at the end
def Chat.cursor.set(seen: List<&2, Seen>, +file: String, +num: U32) -> List<&2, Seen>:
  match seen:
    case Nil{}:
      [Seen{file, num}]
    case Con{s, +rest}:
      match s:
        case Seen{+name, old}:
          Chat.cursor.set.if(String.eq(name, file), name, old, num, rest,
            _u => Chat.cursor.set(rest, file, num))

# the cursor as text, one "<lines>\t<file>" line per entry
def Chat.cursor.text(seen: List<&2, Seen>) -> String:
  match seen:
    case Nil{}:
      ""
    case Con{s, rest}:
      match s:
        case Seen{file, num}:
          U32.show(num) ++ "\t" ++ file ++ "\n" ++ Chat.cursor.text(rest)

# --- the claude cursor ---

# one entry of the claude connector's cursor: a transcript file, relative
# to the root, how many of its complete lines have been read, and the
# bytes they take, None in an entry a cursor before byte offsets wrote
type At is Data:
  At{file: String, lines: U32, bytes: Maybe<&2, U32>}

# where a read of a file starts: the byte, the lines before it, and how
# many complete lines after it were read before
type From is Data:
  From{byte: U32, lines: U32, skip: U32}

# where a file's next read starts: an entry with its bytes reads on from
# them; an entry without reads from byte 0 and skips its lines
def Chat.from(at: At) -> From:
  match at:
    case At{_file, lines, bytes}:
      match bytes:
        case Some{b}:
          From{b, lines, 0}
        case None{}:
          From{0, 0, lines}

# the bytes up to and with the last line feed of bs, seen the bytes before
# bs and last the answer so far; a loop
def Chat.cut.go(bs: List<&2, U32>, +seen: Nat, last: Nat) -> Nat:
  match bs:
    case Nil{}:
      last
    case Con{b, rest}:
      Chat.cut.go(rest, 1n+seen, Bool.pick(Nat, U32.is_eq(b, 10), 1n+seen, last))

# how many bytes of bs the complete lines take: up to and with its last
# line feed, 0 when it has none
def Chat.cut(bs: List<&2, U32>) -> Nat:
  Chat.cut.go(bs, 0n, 0n)

# the cursor entry after a read of bytes bs from where Chat.from says, and
# the records of its new complete lines, numbered on from those read
def Chat.after.at(
  +file: String,
  from: From,
  +bs: List<&2, U32>,
  +path: String,
  +project: String
) -> At & List<&2, R.Record>:
  match from:
    case From{byte, +lines, +skip}:
      +ls : List<&2, String> = Chat.lines(Chat.utf8(bs))
      (At{file, U32.add(lines, U32.from_nat(List.length(&2, String, ls))),
          Some{U32.add(byte, U32.from_nat(Chat.cut(bs)))}},
        Chat.file(Chat.skip(U32.to_nat(skip), ls), path, project,
          U32.inc(U32.add(lines, skip))))

# a file's cursor entry after reading the bytes bs from Chat.from(at), and
# the records of the lines read
def Chat.after(at: At, +bs: List<&2, U32>, +path: String, +project: String) -> At & List<&2, R.Record>:
  match at:
    case At{+file, lines, bytes}:
      Chat.after.at(file, Chat.from(At{file, lines, bytes}), bs, path, project)

# True when a file of size bytes goes on past where a read starts
def Chat.grown.from(from: From, size: U32) -> Bool:
  match from:
    case From{byte, _lines, _skip}:
      U32.is_gt(size, byte)

# True when a file of size bytes has bytes the entry has not read
def Chat.grown(+at: At, size: U32) -> Bool:
  Chat.grown.from(Chat.from(at), size)

# the new entry, or the old when the file after the bytes is empty
def Chat.at.file(empty: Bool, +rest: String, lines: U32, byte: U32) -> At:
  match empty:
    case True{}:
      At{rest, lines, None{}}
    case False{}:
      At{Chat.after.tab(rest), lines, Some{byte}}

# an entry of its file, lines and the text after them: `<bytes>\t<file>`
# when it reads so, else the old `<file>`
def Chat.at.of(+rest: String, lines: U32, got: Maybe<&2, U32>) -> At:
  match got:
    case Some{b}:
      Chat.at.file(String.is_empty(Chat.after.tab(rest)), rest, lines, b)
    case None{}:
      At{rest, lines, None{}}

# an entry of its lines and the text after the first tab
def Chat.at.lines(got: Maybe<&2, U32>, +rest: String) -> Maybe<&2, At>:
  match got:
    case None{}:
      None{}
    case Some{n}:
      Some{Chat.at.of(rest, n, U32.read(Chat.upto.tab(rest)))}

# an entry from its line: `<lines>\t<bytes>\t<file>`, or `<lines>\t<file>`
# as a cursor before byte offsets wrote it; None when it is neither
def Chat.at.line(+text: String) -> Maybe<&2, At>:
  Chat.at.lines(U32.read(Chat.upto.tab(text)), Chat.after.tab(text))

# the entry ahead of rest, when there is one
def Chat.at.put(got: Maybe<&2, At>, rest: List<&2, At>) -> List<&2, At>:
  match got:
    case None{}:
      rest
    case Some{a}:
      a <> rest

# entries from their lines
def Chat.ats.lines(lines: List<&2, String>) -> List<&2, At>:
  match lines:
    case Nil{}:
      []
    case Con{+text, rest}:
      Chat.at.put(Chat.at.line(text), Chat.ats.lines(rest))

# the claude cursor's entries, one line each; a line that is no entry is
# dropped
def Chat.ats(text: String) -> List<&2, At>:
  Chat.ats.lines(String.lines(text))

# the entry when hit, else what the rest says
def Chat.at.get.if(hit: Bool, at: At, rest: Unit -> At) -> At:
  match hit:
    case True{}:
      at
    case False{}:
      rest(Unit{})

# a file's entry, At{file, 0, Some{0}} when the cursor lists none
def Chat.at.get(ats: List<&2, At>, +file: String) -> At:
  match ats:
    case Nil{}:
      At{file, 0, Some{0}}
    case Con{a, rest}:
      match a:
        case At{+name, lines, bytes}:
          Chat.at.get.if(String.eq(name, file), At{name, lines, bytes},
            _u => Chat.at.get(rest, file))

# the new entry when hit, ahead of the rest, else the old one ahead of
# the rest set
def Chat.at.set.if(hit: Bool, old: At, +at: At, rest: List<&2, At>, more: Unit -> List<&2, At>) -> List<&2, At>:
  match hit:
    case True{}:
      at <> rest
    case False{}:
      old <> more(Unit{})

# the file of an entry
def Chat.at.name(at: At) -> String:
  match at:
    case At{file, _lines, _bytes}:
      file

# the cursor with an entry set: the entry of its file replaced in place,
# or a new entry at the end
def Chat.at.set(ats: List<&2, At>, +at: At) -> List<&2, At>:
  match ats:
    case Nil{}:
      [at]
    case Con{a, +rest}:
      match a:
        case At{+name, lines, bytes}:
          Chat.at.set.if(String.eq(name, Chat.at.name(at)), At{name, lines, bytes},
            at, rest, _u => Chat.at.set(rest, at))

# an entry's line: `<lines>\t<bytes>\t<file>`, or `<lines>\t<file>` when it
# has no bytes
def Chat.at.text(at: At) -> String:
  match at:
    case At{file, lines, bytes}:
      match bytes:
        case Some{b}:
          U32.show(lines) ++ "\t" ++ U32.show(b) ++ "\t" ++ file ++ "\n"
        case None{}:
          U32.show(lines) ++ "\t" ++ file ++ "\n"

# the claude cursor as text, one line per entry
def Chat.ats.text(ats: List<&2, At>) -> String:
  match ats:
    case Nil{}:
      ""
    case Con{a, rest}:
      Chat.at.text(a) ++ Chat.ats.text(rest)

# the code points records take in shards, summed
def Chat.chars(recs: List<&2, R.Record>) -> Nat:
  match recs:
    case Nil{}:
      0n
    case Con{+rec, rest}:
      Nat.add(R.Record.size(rec), Chat.chars(rest))
