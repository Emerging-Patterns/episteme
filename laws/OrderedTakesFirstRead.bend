import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd

# LAW: an example: of two reads of shard 1 the first is taken, and shard
# 2, with no read, gets a failed read "no read".
law ordered_example:
  for u: Unit
  {Rd.Read.ordered([S.Shard{1, [], [], 0, True{}}, S.Shard{2, [], [], 0, False{}}],
      [Rd.Read.fail(1, "b", "second pass"), Rd.Read.fail(1, "a", "first pass")])
    == [Rd.Read.fail(1, "b", "second pass"), Rd.Read.fail(2, "", "no read")]
    : List<&2, Rd.Read>}
