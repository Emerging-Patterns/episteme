# `Chat.decode(js)` is None for a compaction summary and for a line whose
# `type` is a string other than `user`, `assistant` and `attachment`; a
# content block whose `type` is `tool_result` reads as `Back` of its content's
# size, never its text.
#
# `src/chat.bend` decides what a Claude Code transcript line becomes.
# `Chat.decode(js)` reads a line's JSON object as a `Line{author, uuid, ts,
# session, parent, blocks}`: only a line whose `type` is `user` or
# `assistant`, or an `attachment` line that is a queued prompt (below), and
# that is not a compaction summary (`isCompactSummary` true) is read, and it
# needs a non-empty `uuid` and `timestamp`. The author of a user line is
# `agent` in a subagent transcript (`isSidechain` true); else `noah` when its
# `origin.kind` is `human` or it has no origin and it is not `isMeta`; else
# `meta` for an `isMeta` line with a human or no origin; else its
# `origin.kind` (for example `task-notification`). The author of an assistant
# line is its `message.model`. A prompt typed while Claude was busy is an
# `attachment` line whose `attachment.type` is `queued_command`: it is read
# when its `attachment.origin.kind` is `human` (by `noah`) or `channel` (by
# `channel`); one with no origin is a task notification in older transcripts
# and is not read, its body `attachment.prompt` read as message content; every
# other attachment is not read. `parent` is `claude:<parentUuid>`, or empty. A
# string `message.content` is one block of said text; an array's blocks are
# `Said` (a `text` block's text, a `thinking` block's thinking), `Call` (a
# `tool_use` block's name and its input printed as compact JSON), `Back` (a
# `tool_result` block's size in code points: its string, or the sum of its
# items' `text`; never its text) or `Mute` (anything else).
# `Chat.records(path, project, n, l)` gives, in order, the record
# `claude:<uuid>` whose body is the said texts, each followed by a blank line
# (none when that has no paragraph), then for each `Call` or `Back` block at
# index `i` of the content the record `claude:<uuid>:<i>`: a call is by the
# line's author, and its body is its name, a line feed and its input when the
# input has at most `Chat.inline()` (4000) code points, else the pointer body
# `<name>, <size> chars` (the input's code points) with `ptr`
# `file:<path>:<n>`; a result's body is `tool result, <size> chars`, by
# `tool`, with that `ptr`. `file:<path>:<n>` is the transcript's line `n`.
# `Chat.lines(text)` is the complete lines of a text: what follows the last
# line feed is a line still being written and is not one. Closed examples
# check whole lines through `Chat.read`, `Chat.lines` and the cursor text; no
# guarantee rests on them.
import Base
import ../src/chat.bend as C
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# LAW: a compaction summary is never read
law decode_compact:
  for +js: Value.Json
  for h: {Json.as_bool(Json.get(js, "isCompactSummary")) == Some{True{}}
    : Maybe<&2, Bool>}
  {C.Chat.decode(js) == None{} : Maybe<&2, C.Line>}

# LAW: a line whose type is not user, assistant or attachment is not read
law decode_other:
  for +js: Value.Json
  for kind: String
  for hk: {Json.as_str(Json.get(js, "type")) == Some{kind} : Maybe<&2, String>}
  for hu: {String.eq(kind, "user") == False{} : Bool}
  for ha: {String.eq(kind, "assistant") == False{} : Bool}
  for ht: {String.eq(kind, "attachment") == False{} : Bool}
  {C.Chat.decode(js) == None{} : Maybe<&2, C.Line>}

# LAW: a tool result block keeps its size and never its text
law block_result:
  for +js: Value.Json
  for h: {Json.as_str(Json.get(js, "type")) == Some{"tool_result"}
    : Maybe<&2, String>}
  {C.Chat.block(js) == C.Back{C.Chat.size(Json.get(js, "content"))} : C.Block}
