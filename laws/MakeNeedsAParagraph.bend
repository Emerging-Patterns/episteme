# `Record.make` is None exactly when `Para.split` of the body is empty, and
# otherwise a record of the given fields with those paragraphs.
#
# A record is the unit the log stores and the shards pack: `Record{id, ts,
# source, author, thread, parent, paras, ptr}` in `src/record.bend`. `ts` is
# ISO 8601 UTC (`YYYY-MM-DDTHH:MM:SS.mmmZ`), so string order is time order. An
# empty `thread`, `parent` or `ptr` means none. `ptr` says where more of the
# record is to be found when its body is only a pointer to it (`show`
# prints what it points at), or, as "removed", that the record removes its
# id (laws/LiveKeepsLastVersion.bend). `Record.make` splits the body into
# paragraphs with `Para.split`. `Record.to_line` writes a record as one
# compact JSON object with no newline, its paragraphs as
# `[[n,start,end,text],...]`, and `Record.of_line` reads one back.
# `Record.of_line` is None for a line that is no record: not JSON, `id`, `ts`
# or `source` missing or empty, another field not a string, `paras` not a
# non-empty array, or a paragraph not exactly `[n,start,end,text]`; closed
# example laws check this on five lines, and no guarantee rests on it yet.
# laws/RecordLineRoundTrips.bend rests on laws/RecordLineRoundTrips.bend for
# every record; its laws check the round trip on two records, one a pointer
# record with escapes and non-ASCII text.
import Base
import ../src/para.bend as P
import ../src/record.bend as R

# LAW: a body with no paragraphs makes no record
law make_empty:
  for id: String
  for ts: String
  for source: String
  for author: String
  for thread: String
  for parent: String
  for body: String
  for ptr: String
  for h: {P.Para.split(body) == [] : List<&2, P.Para>}
  {R.Record.make(id, ts, source, author, thread, parent, body, ptr)
    == None{} : Maybe<&2, R.Record>}

# LAW: a body with paragraphs makes the record of the given fields with
# those paragraphs
law make_some:
  for id: String
  for ts: String
  for source: String
  for author: String
  for thread: String
  for parent: String
  for body: String
  for ptr: String
  for p: P.Para
  for ps: List<&2, P.Para>
  for h: {P.Para.split(body) == p <> ps : List<&2, P.Para>}
  {R.Record.make(id, ts, source, author, thread, parent, body, ptr)
    == Some{R.Record{id, ts, source, author, thread, parent, p <> ps, ptr}}
    : Maybe<&2, R.Record>}
