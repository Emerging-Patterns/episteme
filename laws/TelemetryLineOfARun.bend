# Every question `ask`, `serve` and `eval` run, refused or not, appends one
# line to `telemetry.jsonl` under the store: `Tele.line` of the run, a JSON
# object with, in order, `ts` (when it was asked), `via` (`ask`, `serve` or
# `eval`), the `question`, its `filter` as written, its `since` (or null),
# `ms` (milliseconds from the question to its excerpts), its exit `code` and
# `refused` (the refusal, "" when it ran), then:
#
# - `sources`: each source the filter hits, before the since, with its
#   `shards`, their `chars` (code points) and `paras`;
# - `shards`: each shard the run read, in run order, by its own name
#   (`source`, `n`), with what went in (`chars`, `paras`), its read (`ok`,
#   `ms`, the count of `labels` it named) and what came out (`out_paras`,
#   `out_chars`: the paragraphs its labels kept and their code points);
# - the run's totals: `in_chars` (the shards read), `excerpts` and
#   `out_chars` (the merged excerpts' paragraph code points).
#
# A shard with no read is not ok, with ms and labels 0. The example pins
# the field names and their order.
#
# The paragraph counts are given to `Tele.line.with` beside the shards, so
# that a frozen shard the question did not read from its file is listed with
# the count its source's sizes file holds (src/store.bend); `Tele.line` is
# that line with every count taken from the shard itself.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/filter.bend as F
import ../src/excerpt.bend as E
import ../src/read.bend as Rd
import ../src/telemetry.bend as T

# a book section of two paragraphs
def tele.rec() -> R.Record:
  R.Record{"s1", "t", "book:x/y", "", "", "",
    [P.Para{1, 0, 10, "0123456789"}, P.Para{2, 12, 15, "abc"}], ""}

# a frozen shard of the section, the third of its source
def tele.shard(num: U32) -> S.Shard:
  S.Shard{num, [S.Item{tele.rec(), 1, 2}], ["book:x/y"], 40, True{}}

# a read of the run's shard 1 that named p2
def tele.read() -> Rd.Read:
  Rd.Read{1, "u", ["p2"], True{}, "", 30, 5, 0, 7}

# LAW: an example: a run of one shard whose read kept one paragraph of
# three code points
law tele_example:
  for u: Unit
  {T.Tele.line("2026-11-03T00:00:00.000Z", "ask", "q?", [F.Prefix{"book:x/"}], None{}, 9n, 0, "",
      [tele.shard(3)], [tele.shard(1)], [Rd.Name{"book:x/y", 3}], [tele.read()],
      [E.Ex{tele.rec(), [P.Para{2, 12, 15, "abc"}]}])
    == "{\"ts\":\"2026-11-03T00:00:00.000Z\",\"via\":\"ask\",\"question\":\"q?\",\"filter\":[\"book:x/\"],\"since\":null,\"ms\":9,\"code\":0,\"refused\":\"\",\"sources\":[{\"source\":\"book:x/y\",\"shards\":1,\"chars\":40,\"paras\":2}],\"shards\":[{\"source\":\"book:x/y\",\"n\":3,\"chars\":40,\"paras\":2,\"ok\":true,\"ms\":7,\"labels\":1,\"out_paras\":1,\"out_chars\":3}],\"in_chars\":40,\"excerpts\":1,\"out_chars\":3}"
    : String}

# LAW: Tele.line is Tele.line.with given each shard's own paragraph count,
# for the shards the filter hits and for those the run read
law tele_counts:
  for ts: String
  for via: String
  for question: String
  for filter: List<&2, F.Sel>
  for since: Maybe<&2, String>
  for ms: Nat
  for code: U32
  for why: String
  for +all: List<&2, S.Shard>
  for +hits: List<&2, S.Shard>
  for names: List<&2, Rd.Name>
  for +rs: List<&2, Rd.Read>
  for +xs: List<&2, E.Ex>
  {T.Tele.line(ts, via, question, filter, since, ms, code, why, all, hits, names, rs, xs)
    == T.Tele.line.with(ts, via, question, filter, since, ms, code, why, all, T.Tele.counts(all),
      hits, T.Tele.counts(hits), names, rs, xs)
    : String}
