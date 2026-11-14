# Claude Code puts reminders of its own, `<system-reminder>` elements, at
# the head of what the user sends: as a text block of their own ahead of the
# typed one, or inside the same text. They are the harness's words, so in a
# line read as the user's (laws/UserLineAuthors.bend) they are not recorded
# under the user's name.
#
# `Chat.parts(text)` reads one text of such a line. A text that does not
# open with `<system-reminder>` is one said block, whole. One that does is
# cut after its last `</system-reminder>`: the text through it is a `Note`
# block, and what follows, unless it is blank, is a `Said` block; with no
# closing mark the text is one said block. `Chat.blocks.by(mine, blocks)`
# does this to each said block of the user's line and to no other block,
# and leaves the blocks of any other author's line as they are.
#
# A note is recorded on its own, as a tool call is (`Chat.tool`): the record
# `claude:<uuid>:<block index>` by `meta`, its text the note's, with no
# pointer; and it is no part of the line's said text (`Chat.said`), so the
# record `claude:<uuid>` by the user holds only what the user sent. Every
# record of the line still carries its stamp
# (laws/ChatRecordsKeepEveryBlock.bend).
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: a text that does not open with a reminder is one said block, whole
law plain_text_is_said:
  for +text: String
  for plain: {String.starts_with(text, "<system-reminder>") == False{} : Bool}
  {C.Chat.parts(text) == [C.Said{text}] : List<&2, C.Block>}

# LAW: a note is recorded on its own, by meta, with its text and no pointer
law note_is_metas_record:
  for ts: String
  for source: String
  for thread: String
  for parent: String
  for ptr: String
  for author: String
  for uuid: String
  for i: U32
  for text: String
  {C.Chat.tool(ts, source, thread, parent, ptr, author, uuid, i, C.Note{text})
    == R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, "meta",
      thread, parent, text, "")
    : Maybe<&2, R.Record>}

# LAW: a note is no part of a line's said text
law note_is_not_said:
  for text: String
  for rest: List<&2, C.Block>
  {C.Chat.said(C.Note{text} <> rest) == C.Chat.said(rest) : String}

# LAW: the blocks of a line that is not the user's are left as they are
law other_lines_keep_their_blocks:
  for blocks: List<&2, C.Block>
  {C.Chat.blocks.by(False{}, blocks) == blocks : List<&2, C.Block>}

# LAW: in the user's line a block that is not said text is left as it is
law mine_keeps_other_blocks:
  for name: String
  for input: String
  for chars: U32
  for rest: List<&2, C.Block>
  {C.Chat.blocks.by(True{}, C.Call{name, input} <> C.Back{chars} <> C.Mute{} <> rest)
    == C.Call{name, input} <> C.Back{chars} <> C.Mute{} <> C.Chat.blocks.by(True{}, rest)
    : List<&2, C.Block>}

# LAW: an example: a reminder block ahead of the typed block, and a
# reminder at the head of the typed text, each give the user's record with
# the typed text alone and meta's record with the reminder
law read_reminder_example:
  for u: Unit
  {List.concat(&2, R.Record, [
      C.Chat.read("/t/-p/s.jsonl", "p", 1,
          "{\"type\":\"user\",\"uuid\":\"u1\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"origin\":{\"kind\":\"human\"},\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"<system-reminder>r</system-reminder>\"},{\"type\":\"text\",\"text\":\"hi\"}]}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 2,
          "{\"type\":\"user\",\"uuid\":\"u2\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"origin\":{\"kind\":\"human\"},\"message\":{\"content\":\"<system-reminder>r</system-reminder> <system-reminder>q</system-reminder>\\n\\nhi\"}}")])
    == [R.Record{"claude:u1", "2026-10-01T10:00:00.000Z", "chat:claude/p", "noah",
        "s", "", [P.Para{1, 0, 2, "hi"}], ""},
      R.Record{"claude:u1:0", "2026-10-01T10:00:00.000Z", "chat:claude/p", "meta",
        "s", "", [P.Para{1, 0, 36, "<system-reminder>r</system-reminder>"}], ""},
      R.Record{"claude:u2", "2026-10-01T10:00:00.000Z", "chat:claude/p", "noah",
        "s", "", [P.Para{1, 2, 4, "hi"}], ""},
      R.Record{"claude:u2:0", "2026-10-01T10:00:00.000Z", "chat:claude/p", "meta",
        "s", "",
        [P.Para{1, 0, 73, "<system-reminder>r</system-reminder> <system-reminder>q</system-reminder>"}],
        ""}]
    : List<&2, R.Record>}
