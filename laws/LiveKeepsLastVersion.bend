# A record's id names its last version: of the records with one id, only
# the last counts, and it counts only when it is not a removal.
#
# `src/live.bend` decides which records are current. The log is append-only,
# so a record is changed by appending a later one with the same id, and
# removed by appending a removal with the id (its ptr is "removed";
# `Live.gone`). `Live.of(xs)` is
# the records of `xs`, in order, that no later record of `xs` has the id of,
# less the removals: appending a record `x` to `xs` drops every record with
# x's id from the current records and puts `x` last, unless `x` is a removal
# (`live_last`). Taking the current records first changes nothing that comes
# after (`live_append`), and records none of which shares an id with an
# earlier record leave the earlier ones' current records as they were and
# follow them (`live_fresh`). `Live.find(id, xs)`, which `episteme
# show` runs over the log in one pass, is the first record with the id among
# `Live.of(xs)`, of which there is at most one: none when no record has the id
# or its last is a removal (`find_live`). A source whose records each have an
# id no earlier record of it has, and none of which is a removal, has every
# record current: for it `Live.of` is the identity.
#
# This file says which version of an id counts, in one list of records: a
# batch's own, or the log's for `show`. It does not say where a source's
# shards keep a changed record: that is at the place of its earlier version,
# not last as in `Live.of` (laws/ChangedRecordKeepsItsPlace.bend).
import Base
import ../src/record.bend as R
import ../src/live.bend as L
import ./defs/CurrentRecords.bend as D1

# LAW: a record appended after xs drops every earlier record with its id
# from the current records and comes last itself, unless it is a removal
law live_last:
  for xs: List<&2, R.Record>
  for +x: R.Record
  {L.Live.of(List.append(&2, R.Record, xs, [x]))
    == List.append(&2, R.Record, D1.without(L.Live.id(x), L.Live.of(xs)), D1.alone(x))
    : List<&2, R.Record>}

# LAW: the current records of xs, followed by ys, have the current records
# xs followed by ys has
law live_append:
  for xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  {L.Live.of(List.append(&2, R.Record, L.Live.of(xs), ys))
    == L.Live.of(List.append(&2, R.Record, xs, ys)) : List<&2, R.Record>}

# LAW: when no record of xs has the id of a record of ys, the current records
# of xs followed by ys are those of xs, then those of ys
law live_fresh:
  for xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +h: {D1.fresh(xs, ys) == True{} : Bool}
  {L.Live.of(List.append(&2, R.Record, xs, ys))
    == List.append(&2, R.Record, L.Live.of(xs), L.Live.of(ys)) : List<&2, R.Record>}

# LAW: show's one-pass find is the record with the id among the current
# records, or none
law find_live:
  for +id: String
  for xs: List<&2, R.Record>
  {L.Live.find(id, xs) == D1.first(id, L.Live.of(xs)) : Maybe<&2, R.Record>}
