import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: a tool result line is one pointer record, by tool, its
# body the result's size, pointing at its line
law read_result_example:
  for u: Unit
  {C.Chat.read("/t/-p/s.jsonl", "p", 4,
      "{\"type\":\"user\",\"uuid\":\"u4\",\"parentUuid\":\"u3\",\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:03.000Z\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":[{\"type\":\"text\",\"text\":\"east room\"}]}]}}")
    == [R.Record{"claude:u4:0", "2026-10-01T10:00:03.000Z", "chat:claude/p",
      "tool", "s", "claude:u3", [P.Para{1, 0, 20, "tool result, 9 chars"}],
      "file:/t/-p/s.jsonl:4"}] : List<&2, R.Record>}
