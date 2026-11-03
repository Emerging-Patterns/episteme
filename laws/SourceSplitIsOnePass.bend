# `Shard.only(s, xs ++ ys) == Shard.only(s, xs) ++ Shard.only(s, ys)`; the
# source of every record of `xs` is one of `Shard.keys(xs)`; and
# `Shard.part(s, Shard.parts(xs)) == Shard.only(s, xs)`: the one-pass split
# holds, for each source, exactly the records `Shard.only` keeps.
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2

# LAW: Shard.only splits over an append: the records of one source in a
# log and then a batch are those in the log, then those in the batch
law only_append:
  for +src: String
  for xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  {S.Shard.only(src, List.append(&2, R.Record, xs, ys))
    == List.append(&2, R.Record, S.Shard.only(src, xs), S.Shard.only(src, ys))
    : List<&2, R.Record>}

# LAW: the parts Shard.parts splits records into hold, for each source,
# exactly the records Shard.only keeps: the one-pass split is the spec's
# filter
law parts_only:
  for +src: String
  for xs: List<&2, R.Record>
  {S.Shard.part(src, S.Shard.parts(xs)) == S.Shard.only(src, xs) : List<&2, R.Record>}

# LAW: every record's source is one of Shard.keys, so every source with a
# record in a batch has its shards extended
law keys_cover:
  for xs: List<&2, R.Record>
  for r: R.Record
  for h: D1.Elem(R.Record, r, xs)
  {D2.mem(D2.rec.source(r), S.Shard.keys(xs)) == True{} : Bool}
