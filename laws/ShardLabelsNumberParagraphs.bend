import Base
import ../src/shard.bend as S
import ./defs/Specification.bend as D1

# the labels p<idx>, p<idx+1>, ... of ps, each with its record's id and its
# paragraph's number
def tags(
  ps: List<&2, S.Shard.Line()>,
  +idx: U32
) -> List<&2, S.Shard.Label()>:
  match ps:
    case Nil{}:
      []
    case Con{head, tail}:
      match head:
        case (r, pa):
          (String.append("p", U32.show(idx)), (D1.rec.id(r), D1.para.n(pa)))
            <> tags(tail, U32.inc(idx))

# LAW: a shard's labels are p1, p2, ... in the order of its paragraphs,
# each with its record's id and its paragraph's number
law labels_cover:
  for s: S.Shard
  {S.Shard.labels(s) == tags(D1.items.cover(D1.shard.items(s)), 1)
    : List<&2, S.Shard.Label()>}
