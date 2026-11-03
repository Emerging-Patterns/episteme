import Base
import ../src/para.bend as P
import ../src/excerpt.bend as E
import ./defs/Specification.bend as D1
import ./defs/ThreeParagraphRecord.bend as D2

# LAW: an example: excerpts as text, each its header line and then its
# paragraphs, apart by a blank line
law excerpt_render_example:
  for u: Unit
  {E.Excerpt.render([E.Ex{D2.trio(), [P.Para{1, 0, 3, "one"},
      P.Para{3, 10, 15, "three"}]},
    E.Ex{D1.at("a", "2026-01-01", [P.Para{1, 0, 1, "x"}]),
      [P.Para{1, 0, 1, "x"}]}])
    == "### r1 | chat:honcho | 2026-10-30T12:00:00.000Z | noah\nr1#1: one\nr1#3: three\n\n### a | book:x/y | 2026-01-01 | \na#1: x\n"
    : String}
