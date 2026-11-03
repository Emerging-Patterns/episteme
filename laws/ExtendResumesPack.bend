# For records with fewer than 2^32 paragraphs, `pack(cap, n, xs ++ ys)` is the
# frozen shards of `pack(cap, n, xs)` followed by `Shard.extend(cap, t, ys)`,
# where `t` is the last shard of `pack(cap, n, xs)`: extending the tail gives
# exactly the shards a pack of the whole log gives from the tail's number on.
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/FrozenShards.bend as D1
import ./defs/Specification.bend as D2

# LAW: appending ys after the tail of pack(cap, n, xs) with Shard.extend
# gives what packing xs ++ ys gives after the frozen shards of packing xs,
# for records with fewer than 2^32 paragraphs
law extend_pack:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for hc: D2.counted(xs)
  {S.Shard.pack(cap, n, List.append(&2, R.Record, xs, ys))
    == List.append(&2, S.Shard, D1.frozen(S.Shard.pack(cap, n, xs)),
      S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, xs), S.Shard{1, [], [], 0, False{}}),
        ys)) : List<&2, S.Shard>}
