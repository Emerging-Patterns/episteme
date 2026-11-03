import Base
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: a compaction summary, a system line and a line that is
# not JSON give no record
law read_none_example:
  for u: Unit
  {List.concat(&2, R.Record, [
      C.Chat.read("/t/-p/s.jsonl", "p", 5,
          "{\"type\":\"user\",\"isCompactSummary\":true,\"uuid\":\"u5\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"message\":{\"content\":\"so far\"}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 6,
          "{\"type\":\"system\",\"uuid\":\"u6\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"content\":\"x\"}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 7, "{\"type\":\"user\",\"uuid\":")])
    == [] : List<&2, R.Record>}
