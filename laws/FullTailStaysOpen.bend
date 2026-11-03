import Base
import ../src/shard.bend as S
import ./defs/FrozenShards.bend as D1

# each shard's number, size and whether it is frozen
def marks(ss: List<&2, S.Shard>) -> List<&2, Sigma<&2, &2, U32, _n => Sigma<&2, &2, U32, _c => Bool>>>:
  match ss:
    case Nil{}:
      []
    case Con{sh, tail}:
      match sh:
        case S.Shard{num, _items, _sources, chars, frozen}:
          (num, (chars, frozen)) <> marks(tail)

# LAW: an example: four sections of 27 code points at a cap of 54 fill two
# shards exactly, numbered from 7; the second is the tail, full but not
# frozen
law shard_full_tail:
  for u: Unit
  {marks(S.Shard.pack(54, 7, [D1.section("A", "a1"), D1.section("A", "a2"),
    D1.section("A", "a3"), D1.section("A", "a4")]))
    == [(7, (54, True{})), (8, (54, False{}))]
    : List<&2, Sigma<&2, &2, U32, _n => Sigma<&2, &2, U32, _c => Bool>>>}
