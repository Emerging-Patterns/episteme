# `Intent.records(t, t, ts)` is `[]`; and when `String.eq(last, text)` is
# False, `Intent.records(last, text, ts)` is the list of none or one record of
# `Record.make("intent@" ++ ts, ts, "intent", "noah", "", "", text, "")`.
#
# `src/intent.bend` decides what the intent file becomes. `intent.md`,
# under the data directory, holds what the user means to do, in their own
# words. The
# cursor is the whole text last ingested. `Intent.records(last, text, ts)` is
# no record when `text` is `last`, else the record `Record.make` gives of the
# id `intent@<ts>`, the time `ts`, the source `intent`, the author `noah`, no
# thread, parent or pointer, and the whole file as the body; a text with no
# paragraph makes none (laws/MakeNeedsAParagraph.bend). A closed example
# checks a first text's record; no guarantee rests on it.
import Base
import ../src/record.bend as R
import ../src/intent.bend as I

# LAW: the text last ingested gives no record
law intent_same:
  for text: String
  for ts: String
  {I.Intent.records(text, text, ts) == [] : List<&2, R.Record>}

# LAW: a text other than the one last ingested gives its record: id
# intent@<ts>, source intent, by noah, no thread, parent or pointer, when
# it has a paragraph
law intent_changed:
  for last: String
  for text: String
  for ts: String
  for h: {String.eq(last, text) == False{} : Bool}
  {I.Intent.records(last, text, ts)
    == I.Intent.list(R.Record.make("intent@" ++ ts, ts, "intent", "noah", "", "", text, ""))
    : List<&2, R.Record>}
