# A changed record keeps its place: after a batch, a source's current records
# are those it had, each where it was and in its last version, less the
# removed, and then the records whose ids are new to the source.
#
# `Live.next(m, ys)` is a source's current records after a batch whose
# records of the source are `ys`, `m` being its current records before: none
# before its first batch, and after each batch what its shards hold
# (laws/SourceShardsHoldCurrentRecords.bend). It is `Live.kept(m, ys)`
# followed by `Live.added(m, Live.of(ys))`. `Live.kept` decides each record
# of `m` on its own and keeps their order (`kept_each`): a record whose id no
# record of `ys` has stays as it is (`kept_unnamed`), and one whose id `ys`
# names gives way, at its place, to the last record of `ys` with the id, or
# to nothing when that one is a removal (`kept_named`, in the words of
# `Live.find`, laws/LiveKeepsLastVersion.bend). `Live.added` is the current
# records of `ys` whose ids `m` lacks: they follow, in the order they have
# among the batch's own current records. So a record changed by a removal of
# its id and a new version in one batch (laws/RecordsInputChanges.bend) is
# read where its earlier version was, among the records that were around it.
# A place lasts as long as its record is current: an id removed in one batch
# and given again in a later one is new to the source and goes last.
#
# The record `next(m, ys)` has with an id is the batch's last version of it
# when the batch names the id, and the one `m` had when it does not
# (`next_current`): no other record changes, and none is lost. When `ys`
# names no id of `m` the batch only adds, and `next(m, ys)` is `m` followed
# by the batch's current records (`next_new`), which is what lets a tail be
# extended. And when no two records of `m` have one id, no two of
# `next(m, ys)` do (`next_distinct`), so each batch finds the source as the
# last one left it.
# also rests on: laws/LiveKeepsLastVersion.bend
import Base
import ../src/record.bend as R
import ../src/live.bend as L
import ./defs/CurrentRecords.bend as D1

# LAW: each record is decided on its own, and the records keep their order
law kept_each:
  for a: List<&2, R.Record>
  for +b: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  {L.Live.kept(List.append(&2, R.Record, a, b), ys)
    == List.append(&2, R.Record, L.Live.kept(a, ys), L.Live.kept(b, ys)) : List<&2, R.Record>}

# LAW: a record whose id no record of the batch has stays as it is
law kept_unnamed:
  for +r: R.Record
  for +ys: List<&2, R.Record>
  for h: {L.Live.has(L.Live.id(r), ys) == False{} : Bool}
  {L.Live.kept([r], ys) == [r] : List<&2, R.Record>}

# LAW: a record whose id the batch names gives way to the batch's last
# record with the id, to nothing when that one is a removal
law kept_named:
  for +r: R.Record
  for +ys: List<&2, R.Record>
  for h: {L.Live.has(L.Live.id(r), ys) == True{} : Bool}
  {L.Live.kept([r], ys) == D1.given(L.Live.find(L.Live.id(r), ys)) : List<&2, R.Record>}

# LAW: a batch that names no id of m leaves m as it is, and its current
# records follow
law next_new:
  for +m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +h: {D1.fresh(m, ys) == True{} : Bool}
  {L.Live.next(m, ys) == List.append(&2, R.Record, m, L.Live.of(ys)) : List<&2, R.Record>}

# LAW: the record with an id after a batch is the batch's last version of
# the id when the batch names it, else the one m had
law next_current:
  for +i: String
  for +m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  {D1.first(i, L.Live.next(m, ys))
    == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, m))
    : Maybe<&2, R.Record>}

# LAW: records no two of which have one id stay so after a batch
law next_distinct:
  for +m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for h: {D1.distinct(m) == True{} : Bool}
  {D1.distinct(L.Live.next(m, ys)) == True{} : Bool}
