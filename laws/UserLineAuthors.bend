# Claude Code marks who started each user line: `origin.kind` is `human` for
# what the user typed, queued or sent from an app, and another kind for a
# task notification, a channel or another session. The harness's own lines
# carry no origin: its reminders, a local command and its output, the mark
# of an interrupted request, the brief written for a session another
# session started, a prompt a script sent. So `Chat.human(side, meta, kind)`
# reads a user line of a main transcript as the user's (author `noah`) only
# when its origin's kind is `human` and it is not meta; a meta line of a
# human's, and any line with no origin, is by `meta`; a line of another
# origin is by that origin's kind; and every user line of a subagent's
# transcript is by `agent`. A question about what the user said
# (`--author`) is then not answered with the harness's text.
#
# A transcript written before Claude Code recorded origins has no line this
# reads as the user's.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: a user line is by noah only when its origin is a human
# and it is not meta; a meta line and a line with no origin are by meta,
# another origin's line by that origin's kind
law read_author_example:
  for u: Unit
  {List.concat(&2, R.Record, [
      C.Chat.read("/t/-p/s.jsonl", "p", 1,
          "{\"type\":\"user\",\"uuid\":\"u1\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"origin\":{\"kind\":\"human\"},\"message\":{\"content\":\"a\"}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 2,
          "{\"type\":\"user\",\"isMeta\":true,\"uuid\":\"u2\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"message\":{\"content\":\"b\"}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 3,
          "{\"type\":\"user\",\"uuid\":\"u3\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"origin\":{\"kind\":\"task-notification\"},\"message\":{\"content\":\"c\"}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 4,
          "{\"type\":\"user\",\"uuid\":\"u4\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"message\":{\"content\":\"d\"}}")])
    == [R.Record{"claude:u1", "2026-10-01T10:00:00.000Z", "chat:claude/p", "noah",
        "s", "", [P.Para{1, 0, 1, "a"}], ""},
      R.Record{"claude:u2", "2026-10-01T10:00:00.000Z", "chat:claude/p", "meta",
        "s", "", [P.Para{1, 0, 1, "b"}], ""},
      R.Record{"claude:u3", "2026-10-01T10:00:00.000Z", "chat:claude/p",
        "task-notification", "s", "", [P.Para{1, 0, 1, "c"}], ""},
      R.Record{"claude:u4", "2026-10-01T10:00:00.000Z", "chat:claude/p", "meta",
        "s", "", [P.Para{1, 0, 1, "d"}], ""}]
    : List<&2, R.Record>}

# LAW: a line with no origin is never the user's, in a main transcript or a
# subagent's, meta or not
law no_origin_is_not_the_users:
  for side: Bool
  for meta: Bool
  {String.eq(C.Chat.human(side, meta, ""), "noah") == False{} : Bool}

# LAW: a human's line in a main transcript is the user's exactly when it is
# not meta
law human_line_is_the_users_unless_meta:
  for meta: Bool
  {String.eq(C.Chat.human(False{}, meta, "human"), "noah") == Bool.not(meta) : Bool}
