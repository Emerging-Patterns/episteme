import Base
import ../src/para.bend as P
import ../src/excerpt.bend as E
import ../src/chat.bend as C
import ./defs/Specification.bend as D1

# LAW: an example: shard 1 gave record a's second paragraph and record b,
# shard 2 gave record a's first and second paragraphs; a is earlier than b
# and c, b and c share a timestamp. a is joined, paragraphs ascending, each
# once, and b keeps its place before c
law merge_example:
  for u: Unit
  {E.Excerpt.merge([[E.Ex{D1.at("b", "2026-01-02", [P.Para{1, 0, 1, "B"}]),
      [P.Para{1, 0, 1, "B"}]},
    E.Ex{D1.at("a", "2026-01-01", [P.Para{1, 0, 1, "x"}, P.Para{2, 2, 3, "y"}]),
      [P.Para{2, 2, 3, "y"}]}],
    [E.Ex{D1.at("c", "2026-01-02", [P.Para{1, 0, 1, "C"}]),
      [P.Para{1, 0, 1, "C"}]},
    E.Ex{D1.at("a", "2026-01-01", [P.Para{1, 0, 1, "x"}, P.Para{2, 2, 3, "y"}]),
      [P.Para{1, 0, 1, "x"}, P.Para{2, 2, 3, "y"}]}]])
    == [E.Ex{D1.at("a", "2026-01-01", [P.Para{1, 0, 1, "x"}, P.Para{2, 2, 3, "y"}]),
      [P.Para{1, 0, 1, "x"}, P.Para{2, 2, 3, "y"}]},
    E.Ex{D1.at("b", "2026-01-02", [P.Para{1, 0, 1, "B"}]),
      [P.Para{1, 0, 1, "B"}]},
    E.Ex{D1.at("c", "2026-01-02", [P.Para{1, 0, 1, "C"}]),
      [P.Para{1, 0, 1, "C"}]}]
    : List<&2, E.Ex>}
