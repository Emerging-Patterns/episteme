import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C

# LAW: an example: an assistant line's thinking and text are one record by
# its model, and its tool call another, the call's name and input JSON
law read_assistant_example:
  for u: Unit
  {C.Chat.read("/t/-p/s.jsonl", "p", 2,
      "{\"type\":\"assistant\",\"uuid\":\"a2\",\"parentUuid\":null,\"sessionId\":\"s\",\"timestamp\":\"2026-10-01T10:00:01.000Z\",\"message\":{\"model\":\"m1\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"hm\",\"signature\":\"x\"},{\"type\":\"text\",\"text\":\"ok\"},{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Read\",\"input\":{\"f\":1}}]}}")
    == [R.Record{"claude:a2", "2026-10-01T10:00:01.000Z", "chat:claude/p", "m1",
        "s", "", [P.Para{1, 0, 2, "hm"}, P.Para{2, 4, 6, "ok"}], ""},
      R.Record{"claude:a2:2", "2026-10-01T10:00:01.000Z", "chat:claude/p", "m1",
        "s", "", [P.Para{1, 0, 12, "Read\n{\"f\":1}"}], ""}] : List<&2, R.Record>}
