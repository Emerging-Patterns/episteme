import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: a prompt queued while Claude was busy is read, by noah
# for a human's and by channel for a channel's
law read_queued_example:
  for u: Unit
  {List.concat(&2, R.Record, [
      C.Chat.read("/t/-p/s.jsonl", "p", 3,
          "{\"type\":\"attachment\",\"uuid\":\"q1\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"attachment\":{\"type\":\"queued_command\",\"prompt\":\"also x\",\"origin\":{\"kind\":\"human\"}}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 4,
          "{\"type\":\"attachment\",\"uuid\":\"q2\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:01.000Z\",\"attachment\":{\"type\":\"queued_command\",\"prompt\":\"ping\",\"origin\":{\"kind\":\"channel\"}}}")])
    == [R.Record{"claude:q1", "2026-10-01T10:00:00.000Z", "chat:claude/p", "noah",
        "s", "", [P.Para{1, 0, 6, "also x"}], ""},
      R.Record{"claude:q2", "2026-10-01T10:00:01.000Z", "chat:claude/p", "channel",
        "s", "", [P.Para{1, 0, 4, "ping"}], ""}] : List<&2, R.Record>}
