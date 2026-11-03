import Base
import ../src/para.bend as P
import ../src/shard.bend as S
import ../src/excerpt.bend as E
import ./defs/ThreeParagraphRecord.bend as D1

# LAW: an example: a reader answers p2, p9 and p2 again on a shard of three
# paragraphs: one excerpt holding the second paragraph, and one unknown label
law resolve_example:
  for u: Unit
  {E.Excerpt.resolve(S.Shard{1, [S.Item{D1.trio(), 1, 3}], ["chat:honcho"], 40,
      True{}}, ["p2", "p9", "p2"])
    == ([E.Ex{D1.trio(), [P.Para{2, 5, 8, "two"}]}], 1)
    : List<&2, E.Ex> & U32}
