# `episteme show` finds a record in its source's shards alone and gives what
# the whole log gives: the current record with the id, none when there is
# none or it was removed.
#
# An id `<source>@<key>` whose key holds no "@" names its source
# (`Live.source`, `source_named`); the books, git and intent connectors
# make every id so, and the claude and Honcho connectors make ids with no
# "@", which name none. That an id `<source>@<key>` is a record of that
# source is trusted, on main.bend: every connector's is, and a caller of
# `episteme ingest records` names ids so. For an id that names a source with a
# directory of shards of the configured size, when the shards are not behind
# the log, `show` reads that one directory and takes the first record with
# the id among the records its shards hold (`Live.pick` over `Live.held`).
# Those shards are `Shard.pack(cap, 1, m)`, `m` the source's current records
# after the batches `bs` of its records the log holds, each batch applied to
# what the ones before it left (`after(bs, [])`,
# laws/SourceShardsHoldCurrentRecords.bend), and that pick is
# `Live.find(id, xs)`, `xs` the records of those batches in log order
# (`flat(bs)`): what a pass over the log gives (`show_shards`), for records
# with fewer than 2^32 paragraphs that each have one. So a changed record
# keeping its place in the shards changes nothing `show` prints. Every other
# id, and every id while the shards are behind the log, is found with
# `Live.find` over the whole log, as before.
# also rests on: laws/LiveKeepsLastVersion.bend,
# laws/ChangedRecordKeepsItsPlace.bend and laws/ShardsGiveBackRecords.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ./defs/CurrentRecords.bend as D1
import ./defs/Specification.bend as D2

# True when no code point of str is "@"
def noat(str: String) -> Bool:
  match str:
    case SNil{}:
      True{}
    case SCon{chr, rest}:
      Bool.and(Bool.not(Char.is_eq(chr, '@')), noat(rest))

# LAW: an id <source>@<key> whose key holds no "@" names its source
law source_named:
  for +src: String
  for +key: String
  for h: {noat(key) == True{} : Bool}
  {L.Live.source(String.append(src, SCon{'@', key})) == Some{src} : Maybe<&2, String>}

# LAW: the record with the id among those the source's shards hold after
# the batches bs is the current record the batches' records give in log
# order, or none
law show_shards:
  for +cap: U32
  for +id: String
  for +bs: List<&2, List<&2, R.Record>>
  for hc: D1.counted_all(bs)
  for hf: D1.filled_all(bs)
  {L.Live.pick(id, L.Live.held(S.Shard.pack(cap, 1, D1.after(bs, []))))
    == L.Live.find(id, D1.flat(bs)) : Maybe<&2, R.Record>}
