# `Filter.recent(Some{t}, ss)` keeps exactly the shards of `ss`, in order,
# that hold an item whose record's `ts` is not before `t`.
#
# A question may also name a time with `--since`. `Filter.since(text)` reads the value: a date `YYYY-MM-DD`
# becomes `YYYY-MM-DDT00:00:00.000Z`, a time `YYYY-MM-DDTHH:MM:SS.mmmZ` is
# kept as it is, and anything else is None; only the shape is checked, digits
# where digits go and the separators where they go. A record's `ts` has that
# shape and is UTC (laws/MakeNeedsAParagraph.bend), so string order is time
# order and "at or after the since" is a string comparison.
# `Filter.since.arg(v)` is `Done{None}` when no `--since` was given,
# `Done{Some{t}}` when `Filter.since` reads the value as `t`, and otherwise
# `Fail` with the text `--since takes YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ,
# not <value>`. `Filter.recent(since, ss)` keeps the shards a question reads
# and `Filter.after(since, xs)` the excerpts it delivers. Shards are packed in
# ingest order, not time order, so a kept shard may also hold older records;
# `Filter.after` drops their excerpts. No shard format
# change: the test reads the shard's items. A question applies it to a
# shard it has not read through the latest record `ts` the source's sizes
# or tailsize file holds, which is trusted (src/ask.bend), not proved here. Closed examples check a date, a
# time and three malformed values (`2026-10-24T05:06Z`, `2026-1-24`,
# `yesterday`), and no guarantee rests on them.
import Base
import ../src/shard.bend as S
import ../src/filter.bend as F
import ./defs/Specification.bend as D1

# True when some item of its is of a record at or after since
def any_after(its: List<&2, S.Item>, +since: String) -> Bool:
  match its:
    case Nil{}:
      False{}
    case Con{it, rest}:
      Bool.or(D1.at_or_after(D1.rec.ts(D1.item.rec(it)), since), any_after(rest, since))

# the shards of ss, in order, that hold an item at or after since
def recent(ss: List<&2, S.Shard>, +since: String) -> List<&2, S.Shard>:
  match ss:
    case Nil{}:
      []
    case Con{+sh, rest}:
      List.filter.put(S.Shard, sh, recent(rest, since),
        any_after(D1.shard.items(sh), since))

# LAW: a since keeps exactly the shards holding an item at or after it, in
# order
law since_shards:
  for +since: String
  for ss: List<&2, S.Shard>
  {F.Filter.recent(Some{since}, ss) == recent(ss, since) : List<&2, S.Shard>}
