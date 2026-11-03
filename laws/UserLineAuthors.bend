import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: a user line is by noah only when it is not meta and its
# origin is a human or absent; a meta line is by meta, another origin's
# line by that origin's kind
law read_author_example:
  for u: Unit
  {List.concat(&2, R.Record, [
      C.Chat.read("/t/-p/s.jsonl", "p", 1,
          "{\"type\":\"user\",\"uuid\":\"u1\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"origin\":{\"kind\":\"human\"},\"message\":{\"content\":\"a\"}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 2,
          "{\"type\":\"user\",\"isMeta\":true,\"uuid\":\"u2\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"message\":{\"content\":\"b\"}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 3,
          "{\"type\":\"user\",\"uuid\":\"u3\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"origin\":{\"kind\":\"task-notification\"},\"message\":{\"content\":\"c\"}}")])
    == [R.Record{"claude:u1", "2026-10-01T10:00:00.000Z", "chat:claude/p", "noah",
        "s", "", [P.Para{1, 0, 1, "a"}], ""},
      R.Record{"claude:u2", "2026-10-01T10:00:00.000Z", "chat:claude/p", "meta",
        "s", "", [P.Para{1, 0, 1, "b"}], ""},
      R.Record{"claude:u3", "2026-10-01T10:00:00.000Z", "chat:claude/p",
        "task-notification", "s", "", [P.Para{1, 0, 1, "c"}], ""}]
    : List<&2, R.Record>}
