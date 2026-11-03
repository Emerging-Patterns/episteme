# `Read.ordered(ss, rs)` holds exactly one read per shard of `ss`: no shard is
# ever unread.
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd

# LAW: Read.ordered gives exactly one read per shard: no shard is unread
law ordered_length:
  for ss: List<&2, S.Shard>
  for +rs: List<&2, Rd.Read>
  {List.length(&2, Rd.Read, Rd.Read.ordered(ss, rs))
    == List.length(&2, S.Shard, ss) : Nat}
