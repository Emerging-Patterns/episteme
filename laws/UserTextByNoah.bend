import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: a user's text is by noah
law read_user_example:
  for u: Unit
  {C.Chat.read("/t/-p/s.jsonl", "p", 1,
      "{\"type\":\"user\",\"uuid\":\"u1\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"message\":{\"content\":\"hi\"}}")
    == [R.Record{"claude:u1", "2026-10-01T10:00:00.000Z", "chat:claude/p", "noah",
      "s", "", [P.Para{1, 0, 2, "hi"}], ""}] : List<&2, R.Record>}
