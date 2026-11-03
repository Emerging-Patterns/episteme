# `Record.of_line(Record.to_line(r)) == Some{r}`, for every record whose
# strings are Unicode scalar values.
#
# Trusted, not proved: ezjson v1.2.0 prints and parses strings losslessly: for
# a string of Unicode scalar values `s`, `as_str` of the value
# `parse(print(str(s)))` puts at its place is `Some{s}`, and a number's
# spelling survives the same round trip.
#
# Why it is trusted: Proved by ezjson's own gate (its
# laws/PrintRoundTrips.bend, laws/QuotedStringReadsBack.bend,
# laws/NumberKeepsSpelling.bend, laws/ReadersReadBuilders.bend and
# laws/SpansReadAsOwned.bend); episteme cites them and never re-proves them.
import Base
import ../src/para.bend as P
import ../src/record.bend as R

# LAW: an example: a chat record reads back from its line. A closed
# example: this guarantee holds for every record by ezjson, trusted above
law line_example:
  for u: Unit
  {R.Record.of_line(R.Record.to_line(R.Record{"m1",
    "2026-10-30T12:00:00.000Z", "chat:honcho", "noah", "", "",
    [P.Para{1, 0, 5, "hello"}, P.Para{2, 7, 12, "world"}], ""}))
    == Some{R.Record{"m1", "2026-10-30T12:00:00.000Z", "chat:honcho",
      "noah", "", "", [P.Para{1, 0, 5, "hello"}, P.Para{2, 7, 12, "world"}],
      ""}} : Maybe<&2, R.Record>}

# LAW: an example: a pointer record in a thread, whose text holds a quote,
# a backslash, a line feed and non-ASCII code points, reads back from its
# line
law line_example_ptr:
  for u: Unit
  {R.Record.of_line(R.Record.to_line(R.Record{"t9",
    "2026-10-30T12:00:01.250Z", "chat:claude/episteme", "tool", "s1", "m1",
    [P.Para{1, 0, 28, "\"dào ♦\" a\\b\n2048 bytes, text"}],
    "file:/home/user/t.jsonl:42"}))
    == Some{R.Record{"t9", "2026-10-30T12:00:01.250Z",
      "chat:claude/episteme", "tool", "s1", "m1",
      [P.Para{1, 0, 28, "\"dào ♦\" a\\b\n2048 bytes, text"}],
      "file:/home/user/t.jsonl:42"}} : Maybe<&2, R.Record>}
