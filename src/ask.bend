# episteme/src/ask: a question fanned out to the reader pool over the
# shards its filter hits, delivered as verbatim excerpts in time order and
# a footer. IO: the trusted shell around Filter, Read and Excerpt.
#
# Trusted, not proved: `episteme ask [--filter <sources>]... [--since <date>]
# [--json] <question>` runs `Ask.run`: `Filter.check` of `Filter.parse` of the
# `--filter` values, refused with the refusal text on stderr and exit 2, and
# `--since` as said below; then the config, `Store.ready(cap)`, which stops
# with exit 1 and names `episteme ingest` when the shards are behind the log
# (src/ingest.bend; ask never syncs), and `Store.shards(cap, f)`, the shards
# of the sources the filter picks (each such shard's `sources` is its one
# source, laws/ShardHoldsOneSource.bend, so these are the shards `Filter.hits`
# keeps), source directories in name order and each source's in ascending
# number, renumbered 1, 2, ... in that order for the run so that reads match
# shards, beside each shard's own name `Read.Name{source, n}`. The footer
# names a failed read `failed <source> shard <n> at <url>: <why>`, and each
# `--json` read holds `"shard"`, its place in the run, then `"source"` and
# `"n"`. With none it asks no reader; else it first sends every instance of
# the configured pool the run notice `Read.notice(names, question)` (the
# run's shards' own names in run order; `Reader.notice`,
# laws/RunNoticeNamesShards.bend), then `Pool.try` reads them with the
# configured pool, by name on the instances whose answer was ranked
# (laws/RankedReadNamesShard.bend). Each shard's read (`Read.ordered`, shard order,
# laws/EveryShardIsRead.bend) is resolved with `Excerpt.resolve` on its labels
# (laws/ReplyIsOkOrFailed.bend), and the per-shard lists go to `Excerpt.merge`
# in that order. Without `--json` it prints `Excerpt.render` of the merged
# excerpts when `Read.fits` passes for `budget_tokens` and `chars_per_token`,
# else writes each source's excerpts to `runs/<ISO time>/<source with / as
# _>.md` (the directory made with `mkdir` without `-p`, so a name in use is
# never shared: `<ISO time>-1`, `-2`, ... up to 99 are tried next) and
# `INDEX.md` (one line per source: file, source, excerpt count, first and last
# ts) under `Store.home()` and prints the directory; then a blank line and
# `Read.footer`, its wall time from the start of the command. With `--json` it
# prints one object `{"excerpts": [{"id", "source", "ts", "author", "paras":
# [[n, start, end, text]]}], "reads": [Read...]}` and the footer on stderr. It
# exits with `Read.code` of the reads.
#
# Why it is trusted: It is IO sequencing over
# laws/FilterHitsChosenSources.bend, laws/ChatFilterNamesAProject.bend,
# laws/SinceKeepsRecentShards.bend, laws/SinceDropsOldExcerpts.bend,
# laws/NoSinceChangesNothing.bend, laws/ResolveKeepsNamedParagraphs.bend,
# laws/MergeOrdersByTime.bend, laws/RecalledMeansOverlap.bend,
# laws/RequestAdmitsOnlyLabels.bend, laws/ReplyIsOkOrFailed.bend,
# laws/EveryShardIsRead.bend, laws/FailedReadsListed.bend,
# laws/ExcerptsFitBudget.bend and the store; `tests/smoke.sh` checks the
# refusal, the refusal when the shards are behind the log, and a pool with no
# healthy instance, and `tests/live.sh` checks a run's excerpts, footer, run
# files and exit codes.
#
# Trusted, not proved: `episteme ask --since <date>` reads the value with
# `Filter.since.arg`, after `Filter.check` passes and before any other step; a
# refusal goes to stderr with exit 2. A since read narrows the run above in
# two places: the shards are `Filter.recent(since, Store.shards(cap, f))`, so
# only those are numbered, read and named, and the merged excerpts are
# `Filter.after(since, ...)` before they are delivered or written. Without
# `--since` the run is the one above (laws/NoSinceChangesNothing.bend), and
# `episteme eval` always runs without one.
#
# Why it is trusted: It is argument passing and IO sequencing over
# laws/SinceKeepsRecentShards.bend, laws/SinceDropsOldExcerpts.bend and
# laws/NoSinceChangesNothing.bend and the run above; `tests/smoke.sh` checks a
# malformed value (exit 2), a since after every record (no shard read, no
# reader asked) and a since before them (the shards are read, and the dead
# pool exits 2).
#
# Trusted, not proved: `Ask.collect`, and so every question `ask`, `serve`
# and `eval` run (via "ask", "serve" and "eval"), appends one line,
# `Tele.line` of the run (laws/TelemetryLineOfARun.bend), to
# `telemetry.jsonl` under `Store.home()`, opened for append and written in
# one write: its ts is `now_iso` at the start of `Ask.collect`, its ms runs
# from then to the run's excerpts (delivery not counted), its code and
# refusal are the refusal's (exit 1 when the shards are behind the log,
# with no shards; exit 2 when no reader is healthy, with no reads) or else
# `Read.code` of the reads and "", and its sources are every shard
# `Store.shards` answers for the filter, before the since. A failed open or
# write is said on stderr (`episteme: telemetry: ...`) and the question goes
# on; telemetry never changes what a question answers or its exit code.
#
# Why it is trusted: It is one append over the pure line;
# `tests/smoke.sh` checks a refused question's line.
import Base
import ./shard.bend as S
import ./filter.bend as F
import ./excerpt.bend as E
import ./read.bend as Rd
import ./store.bend as St
import ./pool.bend as Pl
import ./reader.bend as Rr
import ./telemetry.bend as T
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value
import 0x8abe7473e8854cc69c687ee77b7d72e3/main.bend as Sys

# the shards ss numbered num, num + 1, ... in order: one run reads shards
# of several sources, each numbered from 1, and a read names its shard by
# number
def Ask.number(ss: List<&2, S.Shard>, +num: U32) -> List<&2, S.Shard>:
  match ss:
    case Nil{}:
      []
    case Con{s, rest}:
      match s:
        case S.Shard{_n, items, sources, chars, frozen}:
          S.Shard{num, items, sources, chars, frozen} <> Ask.number(rest, U32.inc(num))

# the reader pool of the settings
def Ask.pool(cfg: St.Config) -> List<&2, St.Slot>:
  match cfg:
    case St.Config{_tokens, _per, pool, _budget}:
      pool

# url ahead of urls when it ranked the run
def Ask.ranked(ranked: Bool, url: String, urls: List<&2, String>) -> List<&2, String>:
  match ranked:
    case True{}:
      url <> urls
    case False{}:
      urls

# the run notice sent to every instance of the pool, in order; answers the
# instances that ranked the run
def Ask.notice(insts: List<&2, St.Slot>, +body: Value.Json) -> IO(List<&2, String>):
  match insts:
    case Nil{}:
      IO.pure(List<&2, String>, [])
    case Con{inst, rest}:
      match inst:
        case St.Slot{+url, _n}:
          do IO<List<&2, String>>:
            ranked : Bool <- Rr.Reader.notice(url, body)
            more : List<&2, String> <- Ask.notice(rest, body)
            return Ask.ranked(ranked, url, more)

# the reads of the shards; no reads, and no reader asked, when there are
# none; None when no reader instance is healthy
def Ask.read(
  +ss: List<&2, S.Shard>,
  +pool: List<&2, St.Slot>,
  +names: List<&2, Rd.Name>,
  +question: String
) -> IO(Maybe<&2, List<&2, Rd.Read>>):
  match ss:
    case Nil{}:
      IO.pure(Maybe<&2, List<&2, Rd.Read>>, Some{[]})
    case Con{_s, _rest}:
      do IO<Maybe<&2, List<&2, Rd.Read>>>:
        ranked : List<&2, String> <- Ask.notice(pool, Rd.Read.notice(names, question))
        Pl.Pool.try(pool, ranked, names, ss, question)

# write each source's excerpts to <source>.md under dir
def Ask.files(srcs: List<&2, String>, +dir: String, +xs: List<&2, E.Ex>) -> IO(Unit):
  match srcs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+src, rest}:
      do IO<Unit>:
        St.Store.save(dir ++ "/" ++ Rd.Read.file(src), E.Excerpt.render(Rd.Read.of_source(src, xs)))
        Ask.files(rest, dir, xs)

# base for idx 0, else base-<idx>
def Ask.name(+base: String, +idx: U32) -> String:
  Bool.pick(String, U32.is_eq(idx, 0), base, base ++ "-" ++ U32.show(idx))

# True when mkdir made the directory
def Ask.made(res: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Bool:
  match res:
    case Fail{_err}:
      False{}
    case Done{(code, _out)}:
      U32.is_eq(code, 0)

# the directory when it was made, else the next name
def Ask.claimed(made: Bool, dir: String, next: Unit -> IO(String)) -> IO(String):
  match made:
    case True{}:
      IO.pure(String, dir)
    case False{}:
      next(Unit{})

# the run directory at base, or base-<idx> for the first idx from 1 that is
# free: mkdir without -p claims it, so two runs in one instant never share
# one; tries at most 100 names
def Ask.claim(tries: Nat, +base: String, +idx: U32) -> IO(String):
  match tries:
    case 0n:
      St.Store.die(String, "no free run directory at " ++ base)
    case 1n+more:
      +dir = Ask.name(base, idx)
      do IO<String>:
        res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("mkdir", [dir], "", 65536, 60000)
        Ask.claimed(Ask.made(res), dir, _u => Ask.claim(more, base, U32.inc(idx)))

# write the excerpts to run files under runs/<now>/: each source's excerpts
# to <source>.md and INDEX.md; answers the directory
def Ask.spill(+xs: List<&2, E.Ex>) -> IO(String):
  do IO<String>:
    stamp : String <- Sys.time.now_iso()
    +runs : String <- St.Store.path("runs")
    St.Store.mkdir(runs)
    +dir : String <- Ask.claim(100n, runs ++ "/" ++ stamp, 0)
    +srcs : List<&2, String> = Rd.Read.sources(xs, [])
    St.Store.save(dir ++ "/INDEX.md", Rd.Read.index(srcs, xs))
    Ask.files(srcs, dir, xs)
    return dir

# print the excerpts when they fit the budget, else write them to run files
# and print where
def Ask.deliver(fits: Bool, text: String, +xs: List<&2, E.Ex>) -> IO(Unit):
  match fits:
    case True{}:
      IO.write(text)
    case False{}:
      do IO<Unit>:
        dir : String <- Ask.spill(xs)
        IO.print(dir)

# print the run: one JSON object, the footer on stderr; or the excerpts,
# then the footer
def Ask.out(
  json: Bool,
  +xs: List<&2, E.Ex>,
  +rs: List<&2, Rd.Read>,
  names: List<&2, Rd.Name>,
  +foot: String,
  +cfg: St.Config
) -> IO(Unit):
  match json:
    case True{}:
      do IO<Unit>:
        IO.print(Rd.Read.report(xs, rs, names))
        IO.print_err(foot)
    case False{}:
      match cfg:
        case St.Config{_tokens, per, _pool, budget}:
          +text = E.Excerpt.render(xs)
          do IO<Unit>:
            Ask.deliver(Rd.Read.fits(String.length(text), budget, per), text, xs)
            IO.print("\n" ++ foot)

# a question's run before delivery: its excerpts merged in time order, its
# reads in shard order, the run's shards' own names, and how many labels
# the shards do not have
type Got is Data:
  Got{xs: List<&2, E.Ex>, rs: List<&2, Rd.Read>, names: List<&2, Rd.Name>, unknown: U32}

# each shard's excerpts merged, those before the since dropped, beside the
# reads and the shards' names
def Ask.got(
  got: List<&2, List<&2, E.Ex>> & U32,
  since: Maybe<&2, String>,
  rs: List<&2, Rd.Read>,
  names: List<&2, Rd.Name>
) -> Got:
  (lists, unknown) = got
  Got{F.Filter.after(since, E.Excerpt.merge(lists)), rs, names, unknown}

# the first source of a shard's sources, or ""
def Ask.source(srcs: List<&2, String>) -> String:
  match srcs:
    case Nil{}:
      ""
    case Con{src, _rest}:
      src

# each shard's own name, its source and number, in order
def Ask.names(ss: List<&2, S.Shard>) -> List<&2, Rd.Name>:
  match ss:
    case Nil{}:
      []
    case Con{s, rest}:
      match s:
        case S.Shard{n, _items, sources, _chars, _frozen}:
          Rd.Name{Ask.source(sources), n} <> Ask.names(rest)

# the run after its reads, printed with the footer; answers the exit code
def Ask.done(got: Got, json: Bool, +cfg: St.Config, +t0: Nat) -> IO(U32):
  match got:
    case Got{+xs, +rs, +names, unknown}:
      do IO<U32>:
        t1 : Nat <- IO.now()
        Ask.out(json, xs, rs, names, Rd.Read.footer(rs, names, unknown, Nat.sub(t1, t0)), cfg)
        return Rd.Read.code(rs)

# why a run did not happen, and the exit code `ask` stops with
type Refusal is Data:
  Refusal{code: U32, why: String}

# the run when the reads came back, else the refusal and its exit code 2
def Ask.came(
  got: Maybe<&2, List<&2, Rd.Read>>,
  +hits: List<&2, S.Shard>,
  since: Maybe<&2, String>,
  names: List<&2, Rd.Name>
) -> Result<&2, &2, Refusal, Got>:
  match got:
    case None{}:
      Fail{Refusal{2, Pl.Pool.none()}}
    case Some{got}:
      +rs = Rd.Read.ordered(hits, got)
      Done{Ask.got(Rd.Read.excerpts(hits, rs), since, rs, names)}

# a question's run or refusal beside what telemetry needs of it: every
# shard the filter hits, the shards it read, numbered for the run, and
# their own names
type Ran is Data:
  Ran{all: List<&2, S.Shard>, hits: List<&2, S.Shard>, names: List<&2, Rd.Name>,
    res: Result<&2, &2, Refusal, Got>}

# the shards' reads when the shards are not behind the log, else the
# refusal and its exit code 1
def Ask.reads(
  behind: Maybe<&2, String>,
  +cap: U32,
  +cfg: St.Config,
  +filter: List<&2, F.Sel>,
  +since: Maybe<&2, String>,
  +question: String
) -> IO(Ran):
  match behind:
    case Some{why}:
      IO.pure(Ran, Ran{[], [], [], Fail{Refusal{1, why}}})
    case None{}:
      do IO<Ran>:
        +all : List<&2, S.Shard> <- St.Store.shards(cap, filter)
        +ss : List<&2, S.Shard> = F.Filter.recent(since, all)
        +hits : List<&2, S.Shard> = Ask.number(ss, 1)
        +names : List<&2, Rd.Name> = Ask.names(ss)
        got : Maybe<&2, List<&2, Rd.Read>> <- Ask.read(hits, Ask.pool(cfg), names, question)
        return Ran{all, hits, names, Ask.came(got, hits, since, names)}

# a result's exit code: its refusal's, else Read.code of its reads
def Ask.code(res: Result<&2, &2, Refusal, Got>) -> U32:
  match res:
    case Fail{Refusal{code, _why}}:
      code
    case Done{Got{_xs, rs, _names, _unknown}}:
      Rd.Read.code(rs)

# a result's refusal, or ""
def Ask.why(res: Result<&2, &2, Refusal, Got>) -> String:
  match res:
    case Fail{Refusal{_code, why}}:
      why
    case Done{_got}:
      ""

# a result's reads, or none
def Ask.rs(res: Result<&2, &2, Refusal, Got>) -> List<&2, Rd.Read>:
  match res:
    case Fail{_r}:
      []
    case Done{Got{_xs, rs, _names, _unknown}}:
      rs

# a result's excerpts, or none
def Ask.xs(res: Result<&2, &2, Refusal, Got>) -> List<&2, E.Ex>:
  match res:
    case Fail{_r}:
      []
    case Done{Got{xs, _rs, _names, _unknown}}:
      xs

# a failed telemetry write on stderr
def Ask.tele.err(res: Result<&1, &1, U32 & String, Unit>, +path: String) -> IO(Unit):
  match res:
    case Fail{(code, why)}:
      IO.print_err("episteme: telemetry: " ++ Sys.err.os(code, why, path))
    case Done{_x}:
      IO.pure(Unit, Unit{})

# a write of a telemetry line, closed; a failure is said on stderr and
# never stops the question
def Ask.wrote(pair: File & Result<&1, &1, U32 & String, Unit>, +path: String) -> IO(Unit):
  match pair:
    case (handle, res):
      do IO<Unit>:
        File.close(handle)
        Ask.tele.err(res, path)

# the line appended to the open telemetry file, or the failed open said
def Ask.opened(res: Result<&1, &1, U32 & String, File>, +line: String, +path: String) -> IO(Unit):
  match res:
    case Fail{(code, why)}:
      IO.print_err("episteme: telemetry: " ++ Sys.err.os(code, why, path))
    case Done{handle}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(handle, line ++ "\n")
        Ask.wrote(pair, path)

# append a line to telemetry.jsonl under the store, in one write
def Ask.tele(+line: String) -> IO(Unit):
  do IO<Unit>:
    +path : String <- St.Store.path("telemetry.jsonl")
    res : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
    Ask.opened(res, line, path)

# the run's result after its telemetry line
def Ask.logged(
  ran: Ran,
  ts: String,
  via: String,
  question: String,
  filter: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  ms: Nat
) -> IO(Result<&2, &2, Refusal, Got>):
  match ran:
    case Ran{all, hits, names, +res}:
      do IO<Result<&2, &2, Refusal, Got>>:
        Ask.tele(T.Tele.line(ts, via, question, filter, since, ms, Ask.code(res), Ask.why(res),
          all, hits, names, Ask.rs(res), Ask.xs(res)))
        return res

# a question over the shards a passed filter hits, with the settings cfg:
# refused (exit 1) when the shards are behind the log (reads never write),
# else read the shards the filter hits that hold a record at or after the
# since with the pool, refused (exit 2) when no reader instance is healthy,
# resolve each read, merge and drop the excerpts before the since; delivers
# nothing, so `ask`, `serve` and the eval share it, each naming itself as
# via in the telemetry line every question appends
def Ask.collect(
  +via: String,
  +cfg: St.Config,
  +filter: List<&2, F.Sel>,
  +since: Maybe<&2, String>,
  +question: String
) -> IO(Result<&2, &2, Refusal, Got>):
  do IO<Result<&2, &2, Refusal, Got>>:
    ts : String <- Sys.time.now_iso()
    t0 : Nat <- IO.now()
    +cap : U32 <- St.Store.cap(cfg)
    behind : Maybe<&2, String> <- St.Store.behind(cap)
    ran : Ran <- Ask.reads(behind, cap, cfg, filter, since, question)
    t1 : Nat <- IO.now()
    Ask.logged(ran, ts, via, question, filter, since, Nat.sub(t1, t0))

# the run, or stop with its refusal: exit 1 through the store (which frees
# an ingest's lock), else with its code
def Ask.gathered(res: Result<&2, &2, Refusal, Got>) -> IO(Got):
  match res:
    case Done{got}:
      IO.pure(Got, got)
    case Fail{Refusal{+code, +why}}:
      Bool.pick(IO(Got), U32.is_eq(code, 1), St.Store.die(Got, why),
        IO.die(Got, code, "episteme: " ++ why))

# Ask.collect, stopping with its refusal
def Ask.gather(
  +via: String,
  +cfg: St.Config,
  +filter: List<&2, F.Sel>,
  +since: Maybe<&2, String>,
  +question: String
) -> IO(Got):
  do IO<Got>:
    res : Result<&2, &2, Refusal, Got> <- Ask.collect(via, cfg, filter, since, question)
    Ask.gathered(res)

# a question over the shards a passed filter hits, from the since on
def Ask.go(+filter: List<&2, F.Sel>, +since: Maybe<&2, String>, +question: String, +json: Bool) -> IO(U32):
  do IO<U32>:
    +t0 : Nat <- IO.now()
    +cfg : St.Config <- St.Store.config()
    got : Got <- Ask.gather("ask", cfg, filter, since, question)
    Ask.done(got, json, cfg, t0)

# the refusal on stderr and exit 2
def Ask.refuse(why: String) -> IO(U32):
  do IO<U32>:
    IO.print_err("episteme: " ++ why)
    return 2

# the question asked when the --since value read, else its refusal
def Ask.dated(
  res: Result<&2, &2, String, Maybe<&2, String>>,
  +filter: List<&2, F.Sel>,
  +question: String,
  +json: Bool
) -> IO(U32):
  match res:
    case Fail{why}:
      Ask.refuse(why)
    case Done{since}:
      Ask.go(filter, since, question, json)

# the --since value read when the check passed, else the refusal and exit 2
def Ask.checked(
  res: Result<&2, &2, String, Unit>,
  +filter: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  +question: String,
  +json: Bool
) -> IO(U32):
  match res:
    case Fail{why}:
      Ask.refuse(why)
    case Done{_u}:
      Ask.dated(F.Filter.since.arg(since), filter, question, json)

# ask a question: refused with exit 2 when the filter or the --since value
# is, else read every shard the filter hits that holds a record at or after
# the since; answers the exit code, 1 when a read failed
def Ask.run(+filter: List<&2, F.Sel>, since: Maybe<&2, String>, +question: String, +json: Bool) -> IO(U32):
  Ask.checked(F.Filter.check(filter), filter, since, question, json)

# --- for the server ---

# the excerpts when they fit the budget, else the run files' directory and
# their INDEX.md
def Ask.text(fits: Bool, text: String, +xs: List<&2, E.Ex>) -> IO(String):
  match fits:
    case True{}:
      IO.pure(String, text)
    case False{}:
      do IO<String>:
        dir : String <- Ask.spill(xs)
        return "The excerpts are over the budget; they are in " ++ dir ++ ":\n\n"
          ++ Rd.Read.index(Rd.Read.sources(xs, []), xs)

# a run delivered as text: the excerpts (or where they were written), a
# blank line and the footer
def Ask.told(got: Got, +cfg: St.Config, +t0: Nat) -> IO(String):
  match got:
    case Got{+xs, +rs, +names, unknown}:
      match cfg:
        case St.Config{_tokens, per, _pool, budget}:
          +text = E.Excerpt.render(xs)
          do IO<String>:
            body : String <- Ask.text(Rd.Read.fits(String.length(text), budget, per), text, xs)
            t1 : Nat <- IO.now()
            return body ++ "\n" ++ Rd.Read.footer(rs, names, unknown, Nat.sub(t1, t0))

# the run as text, or its refusal
def Ask.reply(res: Result<&2, &2, Refusal, Got>, +cfg: St.Config, +t0: Nat) -> IO(Result<&2, &2, String, String>):
  match res:
    case Fail{Refusal{_code, why}}:
      IO.pure(Result<&2, &2, String, String>, Fail{why})
    case Done{got}:
      do IO<Result<&2, &2, String, String>>:
        text : String <- Ask.told(got, cfg, t0)
        return Done{text}

# a question whose since value read, from the since on
def Ask.answer.dated(
  res: Result<&2, &2, String, Maybe<&2, String>>,
  +filter: List<&2, F.Sel>,
  +question: String
) -> IO(Result<&2, &2, String, String>):
  match res:
    case Fail{why}:
      IO.pure(Result<&2, &2, String, String>, Fail{why})
    case Done{since}:
      do IO<Result<&2, &2, String, String>>:
        +t0 : Nat <- IO.now()
        +cfg : St.Config <- St.Store.config()
        got : Result<&2, &2, Refusal, Got> <- Ask.collect("serve", cfg, filter, since, question)
        Ask.reply(got, cfg, t0)

# a question over a filter that passed its check, answered as text rather
# than printed: the excerpts and footer `ask` prints, or a refusal (a
# malformed since, shards behind the log, no healthy reader) that `ask`
# would stop with
def Ask.answer(
  +filter: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  +question: String
) -> IO(Result<&2, &2, String, String>):
  Ask.answer.dated(F.Filter.since.arg(since), filter, question)
