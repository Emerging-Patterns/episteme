import Base
import ../src/para.bend as P
import ../src/record.bend as R

# LAW: an example: a record's header, and its size, the header's 53 code
# points and its paragraphs' 10
law header_chars_example:
  for u: Unit
  Pair({R.Record.header(R.Record{"m1", "2026-10-30T12:00:00.000Z",
    "chat:honcho", "noah", "", "",
    [P.Para{1, 0, 5, "hello"}, P.Para{2, 7, 12, "world"}], ""})
    == "== chat:honcho | 2026-10-30T12:00:00.000Z | noah | m1" : String},
    {R.Record.chars(R.Record{"m1", "2026-10-30T12:00:00.000Z",
      "chat:honcho", "noah", "", "",
      [P.Para{1, 0, 5, "hello"}, P.Para{2, 7, 12, "world"}], ""})
      == 63 : U32})
