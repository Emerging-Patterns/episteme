# Every paragraph of the input appears in exactly one item of exactly one
# shard, in input order.
#
# `Shard.pack(cap, next_n, records)` in `src/shard.bend` packs records, in
# order, into shards numbered from `next_n`, the unit one reader reads whole.
# An item `Item{rec, from, upto}` is the paragraphs at positions `from` to
# `upto` (1-based, inclusive) of its record, and its size is the record
# header's length plus those paragraphs' text lengths, in code points; a
# record's size is that of its whole item, and `Record.chars` is that size as
# a U32. Records join the open shard whole while they fit in `cap`; when the
# next one does not fit, the open shard freezes, and a record larger than
# `cap` is cut at paragraph boundaries into items that each fill a shard.
# Every shard but the last is frozen; the last is the tail, even when full. A
# shard's `chars` is the sum of its items' sizes and its `sources` the sorted,
# de-duplicated sources of its items. `Shard.render` writes each item's
# `Record.header` line, then one `[p<k>] <text>` per paragraph, `k` counting
# from 1 across the shard, items apart by a blank line, and `Shard.labels`
# maps each `p<k>` to its record id and paragraph number (`labels_cover`,
# laws/ShardLabelsNumberParagraphs.bend). The laws that read item positions
# hold for records with fewer than 2^32 paragraphs.
# laws/FrozenShardsFitCap.bend's precondition is that each record's header,
# alone and with any one of its paragraphs, fits in `cap`: so it is when `cap`
# is at least `2 * Para.max()`, as episteme's shard size always is, paragraphs
# are at most `Para.max()` (laws/ParagraphsCutAtMax.bend) and headers at most
# `Para.max()`. Nothing in the core bounds a header's length; ingest enforces
# it: `Ingest.run` appends only records `Record.fits` passes, whose header is
# at most `Para.max()` code points (laws/IngestKeepsRecordsThatFit.bend,
# src/ingest.bend), and reports the rest on stderr. A closed example checks
# that an exactly full tail stays unfrozen. A closed example packs one book A
# of five sections into shards whose sources are `[A] [A] [A]`, the last the
# tail. `Shard.to_json` writes a shard as one compact JSON object, each item's
# record as `Record.to_json` writes it, and `Shard.of_json` reads one back,
# None when a field is missing or of the wrong kind, an item's record is no
# record by `Record.of_json`, or an item's positions are not `1 <= from <=
# upto <=` its record's paragraph count; closed examples check a round trip,
# four malformed shards and a rendered shard, and no guarantee rests on them.
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/Specification.bend as D1

# the paragraphs shards hold, in order, each beside its record
def shards.cover(ss: List<&2, S.Shard>) -> List<&2, S.Shard.Line()>:
  match ss:
    case Nil{}:
      []
    case Con{s, tail}:
      List.append(&2, S.Shard.Line(), D1.items.cover(D1.shard.items(s)),
        shards.cover(tail))

# LAW: the shards' items, read in order, hold every paragraph of the input,
# in order, each once, beside its record; for records with fewer than 2^32
# paragraphs
law shard_cover:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  for h: D1.counted(xs)
  {shards.cover(S.Shard.pack(cap, n, xs)) == D1.cover(xs)
    : List<&2, S.Shard.Line()>}
