# A shard's `sources` is exactly the set of its items' sources, sorted.
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2

# a shard's sources
def shard.sources(sh: S.Shard) -> List<&2, String>:
  match sh:
    case S.Shard{_n, _items, sources, _chars, _frozen}:
      sources

# LAW: a shard's sources are ascending with no two equal, and a text is
# one of them exactly when it is the source of one of the shard's items
law shard_sources:
  for cap: U32
  for n: U32
  for xs: List<&2, R.Record>
  for s: S.Shard
  for hs: D1.Elem(S.Shard, s, S.Shard.pack(cap, n, xs))
  for x: String
  Pair({D2.ascending(shard.sources(s)) == True{} : Bool},
    {D2.mem(x, shard.sources(s)) == D2.has(x, D2.shard.items(s)) : Bool})
