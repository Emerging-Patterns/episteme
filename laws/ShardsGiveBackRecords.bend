# A source's shards give back the records they were packed from, in order,
# each once. Internal behavior of src/live.bend, not interface.
#
# `Live.held(ss)` reads the records shards hold: the record of each run of
# consecutive paragraphs of one record id, in order, the shards' items read
# in order (`Shard.lines`). Packing records `xs` and reading them back gives
# `xs` exactly when every record of `xs` has a paragraph and no record of
# `xs` has the id of the one before it (a source's current records are such
# a list: no two of them have one id, laws/ChangedRecordKeepsItsPlace.bend),
# for records with fewer than 2^32 paragraphs.
# This is what lets a source's shards be packed again from what they hold,
# with no read of the log (laws/SourceShardsHoldCurrentRecords.bend).
# also rests on: laws/ShardsCoverEveryParagraph.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ./defs/CurrentRecords.bend as D1
import ./defs/Specification.bend as D2

# LAW: the records packed shards hold, read back, are the records packed,
# when each has a paragraph and none has the id of the one before it
law held_pack:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  for hc: D2.counted(xs)
  for hf: D1.filled(xs)
  for ha: {D1.apart(xs, None{}) == True{} : Bool}
  {L.Live.held(S.Shard.pack(cap, n, xs)) == xs : List<&2, R.Record>}
