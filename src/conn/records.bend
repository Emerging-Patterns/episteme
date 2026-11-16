# episteme/src/conn/records: the records input. A caller gives records as
# JSON lines, each one record as the log stores it (src/intake.bend), and
# episteme stores them, keeping each id's last version. IO: the trusted
# shell around Intake.plan.
#
# Trusted, not proved: `episteme ingest records <file> [--complete]` reads
# the whole file (`-` is standard input, read as /dev/stdin; a file it cannot
# read stops the run with exit 1) and reads each non-empty line with
# `Intake.lines`; when a line is no record it stops with exit 1 naming the
# line's number, before it appends anything. Then, for each source the
# records name, in the order they first come (`Intake.sources`), it takes
# that source's records, the last of each id (`Intake.last`), reads every
# shard of the source of the configured size (none when it has none) and
# their records (`Live.held`, its current records:
# laws/SourceShardsHoldCurrentRecords.bend), and appends
# `Intake.plan(complete, held, records)` with one `Ingest.run` whose cursor is
# empty, so the next source is read after this one is packed. When the plan
# has no record it appends nothing. It prints `<source>: <n> records`. No
# cursor is needed: what is current is read from the store.
#
# Why it is trusted: It reads a file and the shards, which no law reaches;
# what a run appends is laws/RecordsInputChanges.bend. `tests/smoke.sh`
# checks a first run, a run with nothing new appending nothing, a new, a
# changed and a removed record (`show` gives only the current version and
# exits 1 for the removed one), a refused line, and two sources in one run.
import Base
import ../record.bend as R
import ../shard.bend as S
import ../live.bend as L
import ../intake.bend as I
import ../store.bend as St
import ../ingest.bend as In

# the path to read: standard input for "-"
def Records.path(+arg: String) -> String:
  Bool.pick(String, String.eq(arg, "-"), "/dev/stdin", arg)

# the records of the lines, or stop naming the first that is none
def Records.parsed(res: Result<&2, &2, U32, List<&2, R.Record>>, +path: String) -> IO(List<&2, R.Record>):
  match res:
    case Fail{num}:
      St.Store.die(List<&2, R.Record>, path ++ ": line " ++ U32.show(num)
        ++ " is no record: it needs the strings id, ts (YYYY-MM-DDTHH:MM:SS.mmmZ) and source, "
        ++ "paras or text with a paragraph, and no ptr removed")
    case Done{recs}:
      IO.pure(List<&2, R.Record>, recs)

# append one source's plan against its current records
def Records.source(+cap: U32, complete: Bool, +src: String, recs: List<&2, R.Record>) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- St.Store.src(cap, src)
    ss : List<&2, S.Shard> <- St.Store.held(dir)
    n : U32 <- In.Ingest.run("records", I.Intake.plan(complete, L.Live.held(ss),
      I.Intake.last(I.Intake.of_source(src, recs))), "")
    IO.print(src ++ ": " ++ U32.show(n) ++ " records")

# append each source's plan, in order
def Records.sources(srcs: List<&2, String>, +cap: U32, +complete: Bool, +recs: List<&2, R.Record>) -> IO(Unit):
  match srcs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+src, rest}:
      do IO<Unit>:
        Records.source(cap, complete, src, recs)
        Records.sources(rest, cap, complete, recs)

# store the records of the input at arg; with complete, each source they
# name is exactly what they hold
def Records.run(+arg: String, complete: Bool) -> IO(Unit):
  do IO<Unit>:
    +path : String = Records.path(arg)
    text : String <- St.Store.read(path)
    +recs : List<&2, R.Record> <- Records.parsed(I.Intake.lines(String.lines(text), 1), path)
    cfg : St.Config <- St.Store.config()
    +cap : U32 <- St.Store.cap(cfg)
    Records.sources(I.Intake.sources(recs, []), cap, complete, recs)
