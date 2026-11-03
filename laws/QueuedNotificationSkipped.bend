import Base
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: a queued task notification, a queued prompt with no
# origin (a task notification in older transcripts) and any other
# attachment give no record
law read_queued_none_example:
  for u: Unit
  {List.concat(&2, R.Record, [
      C.Chat.read("/t/-p/s.jsonl", "p", 3,
          "{\"type\":\"attachment\",\"uuid\":\"q4\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:00.000Z\",\"attachment\":{\"type\":\"queued_command\",\"prompt\":\"done\",\"origin\":{\"kind\":\"task-notification\"}}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 5,
          "{\"type\":\"attachment\",\"uuid\":\"q3\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:02.000Z\",\"attachment\":{\"type\":\"queued_command\",\"prompt\":\"y\"}}"),
      C.Chat.read("/t/-p/s.jsonl", "p", 4,
          "{\"type\":\"attachment\",\"uuid\":\"q5\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:01.000Z\",\"attachment\":{\"type\":\"date\",\"prompt\":\"z\"}}")])
    == [] : List<&2, R.Record>}
