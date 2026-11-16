# A source's shards hold its current records: after every ingest, the shards
# of one size of a source `s` are `Shard.pack(cap, 1, Live.of(xs))`, `xs` the
# records of `s` in log order (laws/LiveKeepsLastVersion.bend), so `ask` reads
# only the last version of each record id and never a removed one.
#
# Ingest keeps this one log batch at a time, in two ways. When the batch's
# records `ys` of `s` hold a removal (`Live.marked`), `s`'s shards are packed
# again from shard 1:
# `Live.repack(cap, ss, ys)` packs the current records of what the shards `ss`
# hold (`Live.held`, laws/ShardsGiveBackRecords.bend) followed by `ys`, which
# is the pack of the current records of `xs ++ ys` (`repack_live`). Otherwise
# the tail is extended with `ys`, as for every source, which is the pack of
# the current records of `xs ++ ys` when `ys` are their own current records
# and no record of `xs` has the id of one of them (`extend_live`). Both hold
# for records with fewer than 2^32 paragraphs, and `repack_live` for records
# that each have a paragraph, as every logged record has
# (laws/MakeNeedsAParagraph.bend). That a batch with no removal meets
# `extend_live`'s conditions is trusted, on src/ingest.bend: a record that
# changes an id comes after a removal of it in its batch
# (laws/RecordsInputChanges.bend), and every other record has an id no record
# of its source had.
# also rests on: laws/ExtendResumesPack.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ./defs/CurrentRecords.bend as D1
import ./defs/Specification.bend as D2
import ./defs/FrozenShards.bend as D3

# LAW: packing again from what the shards of xs's current records hold,
# with ys after, gives the shards of the current records of xs ++ ys
law repack_live:
  for +cap: U32
  for +xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for hc: D2.counted(xs)
  for hf: D1.filled(xs)
  {L.Live.repack(cap, S.Shard.pack(cap, 1, L.Live.of(xs)), ys)
    == S.Shard.pack(cap, 1, L.Live.of(List.append(&2, R.Record, xs, ys)))
    : List<&2, S.Shard>}

# LAW: extending the tail of the shards of xs's current records with ys,
# records that are their own current records and whose ids no record of xs
# has, gives the shards of the current records of xs ++ ys
law extend_live:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for hc: D2.counted(xs)
  for hy: {L.Live.of(ys) == ys : List<&2, R.Record>}
  for hf: {D1.fresh(xs, ys) == True{} : Bool}
  {S.Shard.pack(cap, n, L.Live.of(List.append(&2, R.Record, xs, ys)))
    == List.append(&2, S.Shard, D3.frozen(S.Shard.pack(cap, n, L.Live.of(xs))),
      S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, L.Live.of(xs)), S.Shard{1, [], [], 0, False{}}),
        ys)) : List<&2, S.Shard>}
