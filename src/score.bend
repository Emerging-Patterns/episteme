# episteme/src/score: the eval's scores. How many of a question's gold
# spans its excerpts recall, a question's row, a run's totals with the wall
# time's median and maximum, and the report. Pure: no IO.
import Base
import ./para.bend as P
import ./excerpt.bend as E
import ./read.bend as Rd
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# one question's result: its id, its gold spans recalled and in all, the
# code points of its excerpts' paragraphs, its unknown labels and failed
# shards, its wall milliseconds, and its reads' prompt tokens and their
# milliseconds
type Row is Data:
  Row{id: String, hit: Nat, gold: Nat, chars: Nat, unknown: Nat, failed: Nat,
    ms: Nat, prompt_n: Nat, prompt_ms: Nat}

# a run's totals: its questions, the sums of the rows' counts, and the
# median and maximum of their wall milliseconds
type Total is Data:
  Total{questions: Nat, hit: Nat, gold: Nat, chars: Nat, unknown: Nat,
    failed: Nat, p50: Nat, max: Nat, prompt_n: Nat, prompt_ms: Nat}

# 1 for True, 0 for False
def Score.one(hit: Bool) -> Nat:
  match hit:
    case True{}:
      1n
    case False{}:
      0n

# how many of the gold spans the excerpts recall
def Score.hits(gs: List<&2, E.Gold>, +xs: List<&2, E.Ex>) -> Nat:
  match gs:
    case Nil{}:
      0n
    case Con{g, rest}:
      Nat.add(Score.one(E.Excerpt.recalled(g, xs)), Score.hits(rest, xs))

# the code points of the paragraphs' texts
def Score.para_chars(ps: List<&2, P.Para>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          Nat.add(String.length(text), Score.para_chars(rest))

# the code points of the excerpts' paragraphs' texts
def Score.chars(xs: List<&2, E.Ex>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{x, rest}:
      Nat.add(Score.para_chars(E.Excerpt.paras(x)), Score.chars(rest))

# tokens and milliseconds added to a pair of them
def Score.prompt.add(pn: Nat, pm: Nat, tot: Nat & Nat) -> Nat & Nat:
  (tn, tm) = tot
  (Nat.add(pn, tn), Nat.add(pm, tm))

# the reads' prompt tokens and their milliseconds
def Score.prompt(rs: List<&2, Rd.Read>) -> Nat & Nat:
  match rs:
    case Nil{}:
      (0n, 0n)
    case Con{r, rest}:
      match r:
        case Rd.Read{_shard, _inst, _labels, _ok, _why, pn, pm, _cn, _ms}:
          Score.prompt.add(U32.to_nat(pn), U32.to_nat(pm), Score.prompt(rest))

# a row with its prompt tokens and milliseconds
def Score.row.of(row: Row, tot: Nat & Nat) -> Row:
  match row:
    case Row{id, hit, gold, chars, unknown, failed, ms, _pn, _pm}:
      match tot:
        case (pn, pm):
          Row{id, hit, gold, chars, unknown, failed, ms, pn, pm}

# a question's row from its gold spans, its merged excerpts, its reads, its
# unknown labels and its wall milliseconds
def Score.row(
  id: String,
  +gs: List<&2, E.Gold>,
  +xs: List<&2, E.Ex>,
  +rs: List<&2, Rd.Read>,
  unknown: U32,
  ms: Nat
) -> Row:
  Score.row.of(Row{id, Score.hits(gs, xs), List.length(&2, E.Gold, gs), Score.chars(xs),
    U32.to_nat(unknown), List.length(&2, Rd.Read, Rd.Read.failed(rs)), ms, 0n, 0n},
    Score.prompt(rs))

# --- the median and the maximum ---

# the largest of ns, 0 for none
def Score.max(ns: List<&2, Nat>) -> Nat:
  match ns:
    case Nil{}:
      0n
    case Con{n, rest}:
      Nat.max(n, Score.max(rest))

# x before y and rest when x is at most y, else after y: then ins gives
# rest with x in its place, built only when needed
def Score.slot.if(first: Bool, cur: Nat, other: Nat, rest: List<&2, Nat>, ins: Unit -> List<&2, Nat>) -> List<&2, Nat>:
  match first:
    case True{}:
      cur <> other <> rest
    case False{}:
      other <> ins(Unit{})

# x among ys, which ascend: before the first that is at least x
def Score.slot(+cur: Nat, ys: List<&2, Nat>) -> List<&2, Nat>:
  match ys:
    case Nil{}:
      [cur]
    case Con{+other, +rest}:
      Score.slot.if(Nat.is_le(cur, other), cur, other, rest, _u => Score.slot(cur, rest))

# ns ascending
def Score.sort(ns: List<&2, Nat>) -> List<&2, Nat>:
  match ns:
    case Nil{}:
      []
    case Con{n, rest}:
      Score.slot(n, Score.sort(rest))

# the element at index i of x then rest, or the last when there is none
def Score.at(rest: List<&2, Nat>, head: Nat, idx: Nat) -> Nat:
  match rest idx:
    case Nil{} _:
      head
    case Con{_next, _more} 0n:
      head
    case Con{next, more} 1n+j:
      Score.at(more, next, j)

# the lower median of ascending ns: the element at index (n - 1) / 2, 0
# for none
def Score.mid(ns: List<&2, Nat>) -> Nat:
  match ns:
    case Nil{}:
      0n
    case Con{x, +rest}:
      Score.at(rest, x, Nat.div(List.length(&2, Nat, rest), 2n))

# the lower median of ns, 0 for none
def Score.p50(ns: List<&2, Nat>) -> Nat:
  Score.mid(Score.sort(ns))

# --- the totals ---

# a row's counts added to a total, one more question
def Score.add(row: Row, tot: Total) -> Total:
  match row:
    case Row{_id, hit, gold, chars, unknown, failed, _ms, pn, pm}:
      match tot:
        case Total{q, th, tg, tc, tu, tf, p50, mx, tpn, tpm}:
          Total{1n+q, Nat.add(hit, th), Nat.add(gold, tg), Nat.add(chars, tc),
            Nat.add(unknown, tu), Nat.add(failed, tf), p50, mx,
            Nat.add(pn, tpn), Nat.add(pm, tpm)}

# the rows' counts added up: questions, gold recalled, gold, characters,
# unknown labels, failed shards, prompt tokens and milliseconds
def Score.sum(rows: List<&2, Row>) -> Total:
  match rows:
    case Nil{}:
      Total{0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n}
    case Con{r, rest}:
      Score.add(r, Score.sum(rest))

# the rows' wall milliseconds
def Score.walls(rows: List<&2, Row>) -> List<&2, Nat>:
  match rows:
    case Nil{}:
      []
    case Con{r, rest}:
      match r:
        case Row{_id, _hit, _gold, _chars, _unknown, _failed, ms, _pn, _pm}:
          ms <> Score.walls(rest)

# a total with the median and maximum of walls
def Score.timed(tot: Total, +walls: List<&2, Nat>) -> Total:
  match tot:
    case Total{q, h, g, c, u, f, _p50, _mx, pn, pm}:
      Total{q, h, g, c, u, f, Score.p50(walls), Score.max(walls), pn, pm}

# a run's totals: the rows' sums, and their wall times' median and maximum
def Score.total(+rows: List<&2, Row>) -> Total:
  Score.timed(Score.sum(rows), Score.walls(rows))

# a / b rounded down, 0 when b is 0
def Score.ratio(num: Nat, den: Nat) -> Nat:
  match den:
    case 0n:
      0n
    case 1n+k:
      Nat.div(num, 1n+k)

# --- the report ---

# tenths as "<whole>.<tenth>"
def Score.tenths(+num: Nat) -> String:
  Nat.show(Nat.div(num, 10n)) ++ "." ++ Nat.show(Nat.mod(num, 10n))

# the header of the totals row
def Score.header() -> String:
  "| label | questions | recall | recalled | gold | mean tokens | p50 s | max s | prefill tok/s | failed shards | unknown labels |"

# the totals as one table row: recall in percent with a tenth, the mean
# excerpt tokens at per / 100 characters a token, the median and maximum
# wall seconds with a tenth and the prefill tokens a second
def Score.line(label: String, tot: Total, +per: Nat) -> String:
  match tot:
    case Total{+q, +h, +g, c, u, f, p50, mx, pn, pm}:
      String.concat(["| ", label, " | ", Nat.show(q), " | ",
        Score.tenths(Score.ratio(Nat.mul(1000n, h), g)), "% | ", Nat.show(h), " | ",
        Nat.show(g), " | ", Nat.show(Score.ratio(Nat.mul(100n, c), Nat.mul(per, q))),
        " | ", Score.tenths(Nat.div(p50, 100n)), " | ", Score.tenths(Nat.div(mx, 100n)),
        " | ", Nat.show(Score.ratio(Nat.mul(1000n, pn), pm)), " | ", Nat.show(f),
        " | ", Nat.show(u), " |"])

# a Nat as a JSON number
def Score.num(num: Nat) -> Value.Json:
  Json.num(Nat.show(num))

# a row as JSON
def Score.row.json(row: Row) -> Value.Json:
  match row:
    case Row{id, hit, gold, chars, unknown, failed, ms, pn, pm}:
      Json.obj([("id", Json.str(id)), ("recalled", Score.num(hit)),
        ("gold", Score.num(gold)), ("excerpt_chars", Score.num(chars)),
        ("unknown_labels", Score.num(unknown)), ("failed_shards", Score.num(failed)),
        ("wall_ms", Score.num(ms)), ("prompt_n", Score.num(pn)),
        ("prompt_ms", Score.num(pm))])

# rows as JSON
def Score.rows.json(rows: List<&2, Row>) -> List<&2, Value.Json>:
  match rows:
    case Nil{}:
      []
    case Con{r, rest}:
      Score.row.json(r) <> Score.rows.json(rest)

# the totals as JSON, with the ratios the row prints
def Score.total.json(tot: Total, +per: Nat) -> Value.Json:
  match tot:
    case Total{+q, +h, +g, c, u, f, p50, mx, +pn, +pm}:
      Json.obj([("questions", Score.num(q)), ("recalled", Score.num(h)),
        ("gold", Score.num(g)), ("recall_permille", Score.num(Score.ratio(Nat.mul(1000n, h), g))),
        ("mean_excerpt_tokens", Score.num(Score.ratio(Nat.mul(100n, c), Nat.mul(per, q)))),
        ("p50_wall_ms", Score.num(p50)), ("max_wall_ms", Score.num(mx)),
        ("prompt_n", Score.num(pn)), ("prompt_ms", Score.num(pm)),
        ("prefill_tps", Score.num(Score.ratio(Nat.mul(1000n, pn), pm))),
        ("failed_shards", Score.num(f)), ("unknown_labels", Score.num(u))])

# the report: the label, every row and the totals, as one JSON object
def Score.report(label: String, +rows: List<&2, Row>, +per: Nat) -> String:
  Json.print(Json.obj([("label", Json.str(label)),
    ("rows", Json.arr(Score.rows.json(rows))),
    ("totals", Score.total.json(Score.total(rows), per))]))
