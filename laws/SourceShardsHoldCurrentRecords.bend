# A source's shards hold its current records: after every ingest, the shards
# of one size of a source `s` are `Shard.pack(cap, 1, m)`, `m` the source's
# current records: none before its first batch, and `Live.next(m, ys)` after
# a batch whose records of `s` are `ys`
# (laws/ChangedRecordKeepsItsPlace.bend). So `ask` reads only the last
# version of each record id, never a removed one, and a changed record where
# its earlier version was.
#
# Ingest keeps this one log batch at a time, in two ways. When the batch's
# records `ys` of `s` hold a removal (`Live.marked`), `s`'s shards are packed
# again from shard 1: `Live.repack(cap, ss, ys)` packs `Live.next` of what
# the shards `ss` hold (`Live.held`, laws/ShardsGiveBackRecords.bend) and
# `ys`, which is the pack of `Live.next(m, ys)` (`repack_live`). Otherwise
# the tail is extended with `ys`, as for every source, which is the pack of
# `Live.next(m, ys)` when `ys` are their own current records and no record
# of `m` has the id of one of them (`extend_live`). Both hold for records
# with fewer than 2^32 paragraphs, and `repack_live` for records that each
# have a paragraph, as every logged record has
# (laws/MakeNeedsAParagraph.bend), and no two of which have one id. What a
# batch needs of `m`, the next batch finds again: `Live.next(m, ys)` has
# fewer than 2^32 paragraphs a record (`next_counted`) and a paragraph in
# each (`next_filled`) when `m` and `ys` do, and no two records with one id
# when `m` has none (laws/ChangedRecordKeepsItsPlace.bend). That a batch
# with no removal meets `extend_live`'s conditions is trusted, on
# src/ingest.bend: a record that changes an id comes after a removal of it
# in its batch (laws/RecordsInputChanges.bend), and every other record has
# an id no record of its source had.
# also rests on: laws/ExtendResumesPack.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ./defs/CurrentRecords.bend as D1
import ./defs/Specification.bend as D2
import ./defs/FrozenShards.bend as D3

# LAW: packing again from what the shards of m hold, after the batch ys,
# gives the shards of m's records after the batch
law repack_live:
  for +cap: U32
  for +m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for hc: D2.counted(m)
  for hf: D1.filled(m)
  for hd: {D1.distinct(m) == True{} : Bool}
  {L.Live.repack(cap, S.Shard.pack(cap, 1, m), ys)
    == S.Shard.pack(cap, 1, L.Live.next(m, ys)) : List<&2, S.Shard>}

# LAW: extending the tail of the shards of m with ys, records that are
# their own current records and whose ids no record of m has, gives the
# shards of m's records after the batch
law extend_live:
  for +cap: U32
  for +n: U32
  for +m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for hc: D2.counted(m)
  for hy: {L.Live.of(ys) == ys : List<&2, R.Record>}
  for +hf: {D1.fresh(m, ys) == True{} : Bool}
  {S.Shard.pack(cap, n, L.Live.next(m, ys))
    == List.append(&2, S.Shard, D3.frozen(S.Shard.pack(cap, n, m)),
      S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, m), S.Shard{1, [], [], 0, False{}}),
        ys)) : List<&2, S.Shard>}

# LAW: records with fewer than 2^32 paragraphs each stay so after a batch
# of such records
law next_counted:
  for +m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for hm: D2.counted(m)
  for hy: D2.counted(ys)
  D2.counted(L.Live.next(m, ys))

# LAW: records that each have a paragraph stay so after a batch of such
# records
law next_filled:
  for +m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for hm: D1.filled(m)
  for hy: D1.filled(ys)
  D1.filled(L.Live.next(m, ys))
