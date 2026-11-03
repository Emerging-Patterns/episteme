# episteme/src/intent: what the intent file becomes. intent.md holds
# what the user means to do, in their own words. A run that finds its text
# changed since the text last ingested, which the cursor holds whole,
# makes one record of the whole file; the same text, or a file with no
# paragraph, makes none.
import Base
import ./record.bend as R

# a maybe record as a list of none or one
def Intent.list(got: Maybe<&2, R.Record>) -> List<&2, R.Record>:
  match got:
    case None{}:
      []
    case Some{r}:
      [r]

# the record of the file's text read at ts: id intent@<ts>, source intent,
# author noah, no thread, parent or pointer; None when the text has no
# paragraph
def Intent.record(+text: String, +ts: String) -> Maybe<&2, R.Record>:
  R.Record.make("intent@" ++ ts, ts, "intent", "noah", "", "", text, "")

# none when the text is the one last ingested, else its record
def Intent.records.if(same: Bool, +text: String, +ts: String) -> List<&2, R.Record>:
  match same:
    case True{}:
      []
    case False{}:
      Intent.list(Intent.record(text, ts))

# the records a run appends: none when text is last, the text the cursor
# holds, else the record of text read at ts, when it has a paragraph
def Intent.records(+last: String, +text: String, +ts: String) -> List<&2, R.Record>:
  Intent.records.if(String.eq(last, text), text, ts)
