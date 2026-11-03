# episteme/src/eval: run a questions.jsonl through ask's path and score
# recall against its gold spans. IO: the trusted shell around Score.
#
# Trusted, not proved: `episteme eval <questions.jsonl> --label <name>` reads
# one question a line (`id`, `question`, `filter`, `gold` as eval-import
# writes them; a line that is not one stops it with exit 1). A `--label`
# holding `/` is refused with exit 2, and so, before any read, is a file in
# which some question's filter `Filter.check` refuses (the question's id and
# the refusal on stderr). For each question, in order, it runs `Ask.gather`,
# the path `episteme ask` runs (src/ask.bend: the config, `Store.ready`, so a
# log ahead of the shards stops the eval with exit 1 at its first question,
# the shards the filter hits, `Pool.run`, `Read.ordered`, `Excerpt.resolve`
# and `Excerpt.merge`) in process, delivering nothing, and makes the
# question's row: `Score.hits` of its gold, `Score.chars` of the merged
# excerpts, the unknown labels, the count of `Read.failed`, the gather's wall
# milliseconds and the sums of its reads' `prompt_n` and `prompt_ms`; it
# writes one progress line a question on stderr. Then it writes `{"label",
# "rows": [...], "totals": {...}}` to `report.json` in `runs/eval-<label>-<ISO
# time>/`, a directory claimed as `ask` claims one, prints the directory on
# stderr and the header and totals row of `Score.total` on stdout, and exits
# 0.
#
# Why it is trusted: It is IO sequencing over src/ask.bend's run,
# laws/HitsCountRecalled.bend, laws/TotalSumsRows.bend,
# laws/MedianAndMax.bend, laws/RatioRoundsDown.bend and the store.
# `tests/smoke.sh` checks a question whose filter hits no shard (0 of 1
# recalled, the totals row and the report), a line that is no question (exit
# 1), a refused filter and a label with `/` (exit 2).
import Base
import ./excerpt.bend as E
import ./filter.bend as F
import ./read.bend as Rd
import ./score.bend as Sc
import ./store.bend as St
import ./ask.bend as A
import 0x8abe7473e8854cc69c687ee77b7d72e3/main.bend as Sys
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# an eval question: its id, its text, its filter and its gold spans
type Q is Data:
  Q{id: String, question: String, filter: List<&2, String>, gold: List<&2, E.Gold>}

# --- the questions ---

# a JSON number as a U32, or None
def Eval.u32(got: Maybe<&2, String>) -> Maybe<&2, U32>:
  match got:
    case None{}:
      None{}
    case Some{raw}:
      U32.read(raw)

# a gold span when its fields are there
def Eval.gold.of(source: Maybe<&2, String>, start: Maybe<&2, U32>, end: Maybe<&2, U32>) -> Maybe<&2, E.Gold>:
  match source start end:
    case Some{s} Some{a} Some{b}:
      Some{E.Gold{s, a, b}}
    case _ _ _:
      None{}

# {"source", "start", "end"} as a gold span, or None
def Eval.gold(+js: Value.Json) -> Maybe<&2, E.Gold>:
  Eval.gold.of(Json.as_str(Json.get(js, "source")),
    Eval.u32(Json.as_num(Json.get(js, "start"))), Eval.u32(Json.as_num(Json.get(js, "end"))))

# a gold span ahead of more, or None when either is missing
def Eval.golds.cons(got: Maybe<&2, E.Gold>, more: Maybe<&2, List<&2, E.Gold>>) -> Maybe<&2, List<&2, E.Gold>>:
  match got more:
    case Some{x} Some{xs}:
      Some{x <> xs}
    case _ _:
      None{}

# gold spans, or None when one is not one
def Eval.golds(js: List<&2, Value.Json>) -> Maybe<&2, List<&2, E.Gold>>:
  match js:
    case Nil{}:
      Some{[]}
    case Con{j, rest}:
      Eval.golds.cons(Eval.gold(j), Eval.golds(rest))

# a question when its fields are there
def Eval.q.of(
  id: Maybe<&2, String>,
  question: Maybe<&2, String>,
  filter: Maybe<&2, List<&2, String>>,
  gold: Maybe<&2, List<&2, E.Gold>>
) -> Maybe<&2, Q>:
  match id question filter gold:
    case Some{i} Some{t} Some{f} Some{g}:
      Some{Q{i, t, f, g}}
    case _ _ _ _:
      None{}

# a parsed line as a question, or None
def Eval.q.json(got: Maybe<&2, Value.Json>) -> Maybe<&2, Q>:
  match got:
    case None{}:
      None{}
    case Some{+js}:
      Eval.q.of(Json.as_str(Json.get(js, "id")), Json.as_str(Json.get(js, "question")),
        Rd.Read.arr(Json.get(js, "filter")), Eval.golds(Json.items(Json.get(js, "gold"))))

# a question ahead of more, or None when either is missing
def Eval.qs.cons(got: Maybe<&2, Q>, more: Maybe<&2, List<&2, Q>>) -> Maybe<&2, List<&2, Q>>:
  match got more:
    case Some{x} Some{xs}:
      Some{x <> xs}
    case _ _:
      None{}

# the rest's questions when a line is blank, else the line's ahead of them
def Eval.qs.line(blank: Bool, line: String, more: Maybe<&2, List<&2, Q>>) -> Maybe<&2, List<&2, Q>>:
  match blank:
    case True{}:
      more
    case False{}:
      Eval.qs.cons(Eval.q.json(Json.parse(line)), more)

# the non-blank lines as questions, or None when one is not one
def Eval.qs(lines: List<&2, String>) -> Maybe<&2, List<&2, Q>>:
  match lines:
    case Nil{}:
      Some{[]}
    case Con{+line, rest}:
      Eval.qs.line(String.is_empty(String.trim(line)), line, Eval.qs(rest))

# the questions, or stop
def Eval.need(got: Maybe<&2, List<&2, Q>>, +path: String) -> IO(List<&2, Q>):
  match got:
    case None{}:
      St.Store.die(List<&2, Q>, path ++ ": a line is not a question {id, question, filter, gold}")
    case Some{qs}:
      IO.pure(List<&2, Q>, qs)

# --- the run ---

# the refusal of a question's filter, by its check
def Eval.refusal(res: Result<&2, &2, String, Unit>, +id: String, more: Unit -> Maybe<&2, String>) -> Maybe<&2, String>:
  match res:
    case Fail{why}:
      Some{id ++ ": " ++ why}
    case Done{_u}:
      more(Unit{})

# the first question whose filter ask would refuse, with the refusal, or None
def Eval.refused(qs: List<&2, Q>) -> Maybe<&2, String>:
  match qs:
    case Nil{}:
      None{}
    case Con{quest, rest}:
      match quest:
        case Q{id, _question, filter, _gold}:
          Eval.refusal(F.Filter.check(F.Filter.parse(filter)), id, _u => Eval.refused(rest))

# a row, after its progress line on stderr
def Eval.told(row: Sc.Row) -> IO(Sc.Row):
  match row:
    case Sc.Row{+id, +hit, +gold, +chars, +unknown, +failed, +ms, +pn, +pm}:
      do IO<Sc.Row>:
        IO.print_err(String.concat(["eval ", id, ": recalled ", Nat.show(hit), "/",
          Nat.show(gold), ", ", Nat.show(chars), " chars, ", Nat.show(failed),
          " failed shards, ", Nat.show(unknown), " unknown labels, ", Rd.Read.secs(ms), " s"]))
        return Sc.Row{id, hit, gold, chars, unknown, failed, ms, pn, pm}

# a question's row from its run and its wall time, with a progress line
def Eval.scored(id: String, gold: List<&2, E.Gold>, got: A.Got, ms: Nat) -> IO(Sc.Row):
  match got:
    case A.Got{xs, rs, _names, unknown}:
      Eval.told(Sc.Score.row(id, gold, xs, rs, unknown, ms))

# one question through ask's path, scored
def Eval.one(+cfg: St.Config, quest: Q) -> IO(Sc.Row):
  match quest:
    case Q{+id, +question, filter, +gold}:
      +sels = F.Filter.parse(filter)
      do IO<Sc.Row>:
        t0 : Nat <- IO.now()
        got : A.Got <- A.Ask.gather(cfg, sels, None{}, question)
        t1 : Nat <- IO.now()
        Eval.scored(id, gold, got, Nat.sub(t1, t0))

# every question's row, in order
def Eval.each(+cfg: St.Config, qs: List<&2, Q>) -> IO(List<&2, Sc.Row>):
  match qs:
    case Nil{}:
      IO.pure(List<&2, Sc.Row>, [])
    case Con{q, rest}:
      do IO<List<&2, Sc.Row>>:
        row : Sc.Row <- Eval.one(cfg, q)
        rows : List<&2, Sc.Row> <- Eval.each(cfg, rest)
        return row <> rows

# the configured characters a token, in hundredths
def Eval.per(cfg: St.Config) -> Nat:
  match cfg:
    case St.Config{_tokens, per, _pool, _budget}:
      U32.to_nat(per)

# score every question, write runs/eval-<label>-<time>/report.json, print
# the totals row
def Eval.go(+cfg: St.Config, qs: List<&2, Q>, +label: String) -> IO(U32):
  do IO<U32>:
    +rows : List<&2, Sc.Row> <- Eval.each(cfg, qs)
    stamp : String <- Sys.time.now_iso()
    +runs : String <- St.Store.path("runs")
    St.Store.mkdir(runs)
    +dir : String <- A.Ask.claim(100n, runs ++ "/eval-" ++ label ++ "-" ++ stamp, 0)
    +per : Nat = Eval.per(cfg)
    St.Store.save(dir ++ "/report.json", Sc.Score.report(label, rows, per) ++ "\n")
    IO.print_err(dir)
    IO.print(Sc.Score.header())
    IO.print(Sc.Score.line(label, Sc.Score.total(rows), per))
    return 0

# the run when no filter is refused, else the refusal and exit 2, before
# any read
def Eval.checked(got: Maybe<&2, String>, +cfg: St.Config, qs: List<&2, Q>, +label: String) -> IO(U32):
  match got:
    case Some{why}:
      do IO<U32>:
        IO.print_err("episteme: " ++ why)
        return 2
    case None{}:
      Eval.go(cfg, qs, label)

# the questions' run
def Eval.load(+path: String, +label: String) -> IO(U32):
  do IO<U32>:
    +cfg : St.Config <- St.Store.config()
    text : String <- St.Store.read(path)
    +qs : List<&2, Q> <- Eval.need(Eval.qs(String.lines(text)), path)
    Eval.checked(Eval.refused(qs), cfg, qs, label)

# the run when the label names no subdirectory, else the refusal and exit 2
def Eval.labelled(slash: Bool, +path: String, +label: String) -> IO(U32):
  match slash:
    case True{}:
      do IO<U32>:
        IO.print_err("episteme: a label must not contain /: " ++ label)
        return 2
    case False{}:
      Eval.load(path, label)

# `episteme eval <questions.jsonl> --label <name>`: refuse a label with a /
# or a question whose filter ask refuses, with exit 2; else score every
# question, write runs/eval-<label>-<time>/report.json, print the totals row
def Eval.run(+path: String, +label: String) -> IO(U32):
  Eval.labelled(Nat.is_lt(1n, List.length(&2, String, String.split(label, '/'))), path, label)
