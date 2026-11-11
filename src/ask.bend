# episteme/src/ask: a question fanned out to the reader pool over the
# shards its filter hits, delivered as verbatim excerpts in time order and
# a footer. IO: the trusted shell around Filter, Read and Excerpt.
#
# Trusted, not proved: `episteme ask [--filter <sources>]... [--since <date>]
# [--json] <question>` runs `Ask.run`: `Filter.check` of `Filter.parse` of the
# `--filter` values, refused with the refusal text on stderr and exit 2, and
# `--since` as said below; then the config, `Store.ready(cap)`, which stops
# with exit 1 and names `episteme ingest` when the shards are behind the log
# (src/ingest.bend; ask never syncs), and `Store.light(cap, f)`, the shards
# `Store.shards(cap, f)` answers, a frozen shard of a source with a sizes
# file left unread (see below): the shards
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
# Trusted, not proved: A question does not read a shard's file before the
# reads when its source directory holds its size (`Store.light`: a frozen
# shard's in the sizes file, the tail's in the tailsize file): the shard
# stands in the run with its number, source and code points and no items,
# and telemetry takes its paragraph count from that file. When every instance of the pool ranked the run, each reads by
# name and no request holds a shard's text, so after the reads `Ask.load`
# reads from their files exactly the unread shards whose read named labels
# (a failed read names none), stopping with `<path> is no shard` on one that
# does not parse, and `Read.ordered`, `Excerpt.resolve` and the merge run on
# those; a shard that stays unread had no label to resolve, so the excerpts,
# the reads and the telemetry line are those of reading every file first.
# When some instance did not rank the run (it will be sent shard text),
# every shard of the run is read before the reads. A frozen shard file that
# is no shard so stops only a question that reads it.
#
# Why it is trusted: It is IO sequencing; a ranked instance's request holds
# no shard text by laws/RankedReadNamesShard.bend, and resolving no labels
# keeps no paragraph (laws/ResolveKeepsNamedParagraphs.bend).
#
# Trusted, not proved: `episteme ask --since <date>` reads the value with
# `Filter.since.arg`, after `Filter.check` passes and before any other step; a
# refusal goes to stderr with exit 2. A since read narrows the run above in
# two places: the shards are those `Filter.recent(since, Store.shards(cap,
# f))` keeps (`Ask.recent`: a shard that was read is kept by `Filter.fresh`,
# an unread one when the latest record ts its sizes or tailsize file holds is at or
# after the since, which is the same test, since some record of a shard is
# at or after a time exactly when its latest is), so
# only those are numbered, read and named, and the merged excerpts are
# `Filter.after(since, ...)` before they are delivered or written. Without
# `--since` the run is the one above (laws/NoSinceChangesNothing.bend), and
# `episteme eval` always runs without one.
#
# Why it is trusted: The latest-ts test equals `Filter.fresh` only because
# string order on `ts` is a total order, which no law here proves. Else it is
# argument passing and IO sequencing over
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
# `Store.shards` answers for the filter, before the since; the line is
# `Tele.line.with`, an unread shard's paragraph count the one its source's
# sizes file holds (laws/TelemetryLineOfARun.bend). A failed open or
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
import ezjson@1.2.0.0/src/value.bend as Value
import ezsys@0.1.0.0/main.bend as Sys

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

# a shard numbered num
def Ask.renum(sh: S.Shard, num: U32) -> S.Shard:
  match sh:
    case S.Shard{_n, items, sources, chars, frozen}:
      S.Shard{num, items, sources, chars, frozen}

# whether an unread shard is read now: it has a file, and every shard is
# wanted or its read named labels
def Ask.wanted(path: String, every: Bool, labels: List<&2, String>) -> Bool:
  match path:
    case SNil{}:
      False{}
    case SCon{_head, _tail}:
      match every:
        case True{}:
          True{}
        case False{}:
          match labels:
            case Nil{}:
              False{}
            case Con{_label, _rest}:
              True{}

# sh, or the shard in its file under sh's run number when need
def Ask.load.if(need: Bool, +sh: S.Shard, +path: String) -> IO(S.Shard):
  match need:
    case False{}:
      IO.pure(S.Shard, sh)
    case True{}:
      do IO<S.Shard>:
        got : S.Shard <- St.Store.shard.named(String.ends_with(path, "/tail.json"), path)
        return Ask.renum(got, Rd.Read.n(sh))

# a shard of the run, read from its file when Ask.wanted
def Ask.load.one(+sh: S.Shard, +path: String, every: Bool, rs: List<&2, Rd.Read>) -> IO(S.Shard):
  Ask.load.if(Ask.wanted(path, every, Rd.Read.labels(Rd.Read.find(Rd.Read.n(sh), rs))), sh, path)

# the run's shards beside their files ("" for one already read), each
# unread one read now when every, else when its read in rs named labels;
# a shard with no file beside it is left as it is
def Ask.load(
  ss: List<&2, S.Shard>,
  paths: List<&2, String>,
  +every: Bool,
  +rs: List<&2, Rd.Read>
) -> IO(List<&2, S.Shard>):
  match ss paths:
    case Con{sh, rest} Con{path, more}:
      do IO<List<&2, S.Shard>>:
        one : S.Shard <- Ask.load.one(sh, path, every, rs)
        others : List<&2, S.Shard> <- Ask.load(rest, more, every, rs)
        return one <> others
    case Con{sh, rest} Nil{}:
      IO.pure(List<&2, S.Shard>, sh <> rest)
    case Nil{} _:
      IO.pure(List<&2, S.Shard>, [])

# whether every instance of the pool is among the urls that ranked the run
def Ask.every(insts: List<&2, St.Slot>, +ranked: List<&2, String>) -> Bool:
  match insts:
    case Nil{}:
      True{}
    case Con{inst, rest}:
      match inst:
        case St.Slot{url, _n}:
          Bool.and(Pl.Pool.ranked(ranked, url), Ask.every(rest, ranked))

# the reads, none when there are none
def Ask.named(got: Maybe<&2, List<&2, Rd.Read>>) -> List<&2, Rd.Read>:
  match got:
    case None{}:
      []
    case Some{rs}:
      rs

# a run's reads (None when no reader instance is healthy) beside its
# shards, those the excerpts need read from their files
type Reads is Data:
  Reads{got: Maybe<&2, List<&2, Rd.Read>>, hits: List<&2, S.Shard>}

# read the shards with the pool. When every instance ranked the run, each
# reads by name and needs no shard's text, so the unread shards are read
# from their files only afterwards, and only those whose read named labels;
# else every unread shard is read first
def Ask.read.by(
  ranked_all: Bool,
  +ss: List<&2, S.Shard>,
  paths: List<&2, String>,
  +pool: List<&2, St.Slot>,
  +ranked: List<&2, String>,
  +names: List<&2, Rd.Name>,
  +question: String
) -> IO(Reads):
  match ranked_all:
    case True{}:
      do IO<Reads>:
        +got : Maybe<&2, List<&2, Rd.Read>> <- Pl.Pool.try(pool, ranked, names, ss, question)
        hits : List<&2, S.Shard> <- Ask.load(ss, paths, False{}, Ask.named(got))
        return Reads{got, hits}
    case False{}:
      do IO<Reads>:
        +hits : List<&2, S.Shard> <- Ask.load(ss, paths, True{}, [])
        got : Maybe<&2, List<&2, Rd.Read>> <- Pl.Pool.try(pool, ranked, names, hits, question)
        return Reads{got, hits}

# the reads of the shards, beside the files of the unread ones; no reads,
# and no reader asked, when there are none; None when no reader instance is
# healthy
def Ask.read(
  +ss: List<&2, S.Shard>,
  paths: List<&2, String>,
  +pool: List<&2, St.Slot>,
  +names: List<&2, Rd.Name>,
  +question: String
) -> IO(Reads):
  match ss:
    case Nil{}:
      IO.pure(Reads, Reads{Some{[]}, []})
    case Con{_s, _rest}:
      do IO<Reads>:
        +ranked : List<&2, String> <- Ask.notice(pool, Rd.Read.notice(names, question))
        Ask.read.by(Ask.every(pool, ranked), ss, paths, pool, ranked, names, question)

# the shards of lights, in order
def Ask.shards(ls: List<&2, St.Light>) -> List<&2, S.Shard>:
  match ls:
    case Nil{}:
      []
    case Con{light, rest}:
      match light:
        case St.Light{shard, _sized, _path, _last, _recs}:
          shard <> Ask.shards(rest)

# a light's paragraph count: the one it holds, else its shard's
def Ask.count(sized: Maybe<&2, Nat>, shard: S.Shard) -> Nat:
  match sized:
    case Some{paras}:
      paras
    case None{}:
      Rd.Read.paras(shard)

# the paragraph counts of lights, in order
def Ask.counts(ls: List<&2, St.Light>) -> List<&2, Nat>:
  match ls:
    case Nil{}:
      []
    case Con{light, rest}:
      match light:
        case St.Light{shard, sized, _path, _last, _recs}:
          Ask.count(sized, shard) <> Ask.counts(rest)

# the files of lights, in order, "" for a shard that was read
def Ask.paths(ls: List<&2, St.Light>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{light, rest}:
      match light:
        case St.Light{_shard, _sized, path, _last, _recs}:
          path <> Ask.paths(rest)

# whether a light is of a shard holding a record at or after since: an
# unread shard by its latest record ts, one that was read by Filter.fresh
def Ask.fresh(path: String, last: String, shard: S.Shard, since: String) -> Bool:
  match path:
    case SNil{}:
      F.Filter.fresh(shard, since)
    case SCon{_head, _tail}:
      String.is_ge(last, since)

# light ahead of rest when keep
def Ask.recent.if(keep: Bool, light: St.Light, rest: List<&2, St.Light>) -> List<&2, St.Light>:
  match keep:
    case True{}:
      light <> rest
    case False{}:
      rest

# the lights, in order, of shards holding a record at or after since
def Ask.recent.go(ls: List<&2, St.Light>, +since: String) -> List<&2, St.Light>:
  match ls:
    case Nil{}:
      []
    case Con{light, rest}:
      match light:
        case St.Light{+shard, sized, +path, +last, recs}:
          Ask.recent.if(Ask.fresh(path, last, shard, since), St.Light{shard, sized, path, last, recs},
            Ask.recent.go(rest, since))

# the lights a question with this since reads: all of them without one
def Ask.recent(since: Maybe<&2, String>, ls: List<&2, St.Light>) -> List<&2, St.Light>:
  match since:
    case None{}:
      ls
    case Some{+at}:
      Ask.recent.go(ls, at)

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
  Ran{all: List<&2, S.Shard>, ap: List<&2, Nat>, hits: List<&2, S.Shard>, hp: List<&2, Nat>,
    names: List<&2, Rd.Name>, res: Result<&2, &2, Refusal, Got>}

# the run of reads that came back beside what telemetry needs
def Ask.ran(
  reads: Reads,
  all: List<&2, S.Shard>,
  ap: List<&2, Nat>,
  hp: List<&2, Nat>,
  since: Maybe<&2, String>,
  +names: List<&2, Rd.Name>
) -> Ran:
  match reads:
    case Reads{got, +hits}:
      Ran{all, ap, hits, hp, names, Ask.came(got, hits, since, names)}

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
      IO.pure(Ran, Ran{[], [], [], [], [], Fail{Refusal{1, why}}})
    case None{}:
      do IO<Ran>:
        +ls : List<&2, St.Light> <- St.Store.light(cap, filter)
        +kept : List<&2, St.Light> = Ask.recent(since, ls)
        +ss : List<&2, S.Shard> = Ask.shards(kept)
        +names : List<&2, Rd.Name> = Ask.names(ss)
        reads : Reads <- Ask.read(Ask.number(ss, 1), Ask.paths(kept), Ask.pool(cfg), names, question)
        return Ask.ran(reads, Ask.shards(ls), Ask.counts(ls), Ask.counts(kept), since, names)

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
    case Ran{all, ap, hits, hp, names, +res}:
      do IO<Result<&2, &2, Refusal, Got>>:
        Ask.tele(T.Tele.line.with(ts, via, question, filter, since, ms, Ask.code(res), Ask.why(res),
          all, ap, hits, hp, names, Ask.rs(res), Ask.xs(res)))
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
