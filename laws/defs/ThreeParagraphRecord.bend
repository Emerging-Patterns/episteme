# a record of three paragraphs, for the excerpt examples
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R

# a record of three paragraphs
def trio() -> R.Record:
  R.Record{"r1", "2026-10-30T12:00:00.000Z", "chat:honcho", "noah", "", "",
    [P.Para{1, 0, 3, "one"}, P.Para{2, 5, 8, "two"},
      P.Para{3, 10, 15, "three"}], ""}
