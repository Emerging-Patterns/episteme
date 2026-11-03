# episteme/src/conn/intent: the intent file connector. It reads
# $EPISTEME_HOME/intent.md, which Noah edits, creating it empty when it is
# missing, and appends the record Intent.records gives against the text
# last ingested, which the batch header holds whole as the cursor, like
# every other connector's. IO: the trusted shell.
#
# Trusted, not proved: `episteme ingest intent` reads `<home>/intent.md`
# (src/store.bend's home), first saving it empty when it is missing (errno 2;
# any other failure to read it stops with exit 1), and, when the text is not
# empty, reads its cursor with `Store.cursor("intent")` and appends
# `Intent.records(cursor, text, now)` (laws/IntentAppendsOnChange.bend); an
# empty file appends nothing and reads no cursor, as `Intent.records` of an
# empty text is none for every cursor (laws/EmptyIntentAppendsNothing.bend),
# `now` the clock as ISO 8601 UTC, with one `Ingest.run` whose batch carries
# the whole text as the cursor; when there is no record it appends nothing and
# the cursor stays. It prints `intent: <n> records`. `episteme ingest --all`
# runs the claude, git, intent and honcho connectors in that order, each as
# its own subcommand does; honcho goes last since it stops the run with exit 1
# when Honcho cannot be reached.
#
# Why it is trusted: It reads and saves a file and the clock, which no law
# reaches; what a text becomes is laws/IntentAppendsOnChange.bend and
# laws/EmptyIntentAppendsNothing.bend. `tests/smoke.sh` checks a missing file
# made empty with nothing appended, a first text's record and batch cursor,
# the same text appending nothing, a changed text appending one more, an empty
# file appending nothing, and `--all` printing the claude, git and intent
# lines and then exiting 1 at a Honcho that cannot be reached.
import Base
import ../record.bend as R
import ../intent.bend as I
import ../store.bend as St
import ../ingest.bend as In
import 0x8abe7473e8854cc69c687ee77b7d72e3/main.bend as Sys

# "" after creating the file empty when it is missing (errno 2), else stop
# naming the failure
def Intent.missing(none: Bool, code: U32, why: String, +path: String) -> IO(String):
  match none:
    case True{}:
      do IO<String>:
        St.Store.save(path, "")
        return ""
    case False{}:
      St.Store.die(String, Sys.err.os(code, why, path))

# the file's text: "" when it is missing, after creating it empty; stop
# on any other failure to read it
def Intent.text(res: Result<&1, &1, U32 & String, String>, +path: String) -> IO(String):
  match res:
    case Done{text}:
      IO.pure(String, text)
    case Fail{(+code, why)}:
      Intent.missing(U32.is_eq(code, 2), code, why, path)

# append the records, with the text as the cursor, when there are any
def Intent.append(+recs: List<&2, R.Record>, +text: String) -> IO(U32):
  match recs:
    case Nil{}:
      IO.pure(U32, 0)
    case Con{r, rest}:
      In.Ingest.run("intent", r <> rest, text)

# the records appended for the file's text: none for an empty file, which
# appends nothing whatever the cursor (laws/EmptyIntentAppendsNothing.bend), so its cursor is never
# looked up; else those Intent.records gives against the cursor
def Intent.ingest(empty: Bool, +text: String) -> IO(U32):
  match empty:
    case True{}:
      IO.pure(U32, 0)
    case False{}:
      do IO<U32>:
        +now : String <- Sys.time.now_iso()
        last : String <- St.Store.cursor("intent")
        Intent.append(I.Intent.records(last, text, now), text)

# ingest intent.md when its text changed since the last run; prints how
# many records were appended
def Intent.run() -> IO(Unit):
  do IO<Unit>:
    +home : String <- St.Store.home()
    St.Store.mkdir(home)
    +path : String = home ++ "/intent.md"
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(path)
    +text : String <- Intent.text(res, path)
    n : U32 <- Intent.ingest(String.is_empty(text), text)
    IO.print("intent: " ++ U32.show(n) ++ " records")
