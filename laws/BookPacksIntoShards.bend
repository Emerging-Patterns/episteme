import Base
import ../src/shard.bend as S
import ./defs/FrozenShards.bend as D1

# LAW: an example: one book A of five sections, each 27 code points, two
# to a shard of 60, as a source's shards are packed: two full shards and
# the tail, each of source A, and only the last is the tail
law shard_example:
  for u: Unit
  {D1.sums(S.Shard.pack(60, 1, [D1.section("A", "a1"), D1.section("A", "a2"),
      D1.section("A", "a3"), D1.section("A", "a4"), D1.section("A", "a5")]))
    == [(["A"], True{}), (["A"], True{}), (["A"], False{})]
    : List<&2, Sigma<&2, &2, List<&2, String>, _l => Bool>>}
