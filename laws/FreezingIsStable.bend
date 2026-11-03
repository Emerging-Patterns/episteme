# Freezing is stable: `pack(cap, n, xs ++ ys)` and `pack(cap, n, xs)` agree on
# every shard that `pack(cap, n, xs)` marks frozen (appending never changes a
# frozen shard).
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/FrozenShards.bend as D1

# LAW: the frozen shards of pack(xs) are the first shards of
# pack(xs ++ ys): appending never changes a frozen shard
law shard_stable:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  exs zs: List<&2, S.Shard>
  {S.Shard.pack(cap, n, List.append(&2, R.Record, xs, ys))
    == List.append(&2, S.Shard, D1.frozen(S.Shard.pack(cap, n, xs)), zs)
    : List<&2, S.Shard>}
