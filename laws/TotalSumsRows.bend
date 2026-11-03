# `Score.total(rows)` holds the number of rows and the sums over them of gold
# recalled, gold, excerpt characters, unknown labels, failed shards, prompt
# tokens and prompt milliseconds; when every row's gold recalled is at most
# its gold, so is the total's.
import Base
import ../src/score.bend as Sc

# pointwise sums of two lists of counts
def counts.add(xs: List<&2, Nat>, ys: List<&2, Nat>) -> List<&2, Nat>:
  match xs ys:
    case Con{x, xr} Con{y, yr}:
      Nat.add(x, y) <> counts.add(xr, yr)
    case _ _:
      []

# a row's counts: one question, then gold recalled, gold, characters,
# unknown labels, failed shards, prompt tokens and prompt milliseconds
def row.counts(row: Sc.Row) -> List<&2, Nat>:
  match row:
    case Sc.Row{_id, hit, gold, chars, unknown, failed, _ms, pn, pm}:
      [1n, hit, gold, chars, unknown, failed, pn, pm]

# the rows' counts summed
def rows.counts(rows: List<&2, Sc.Row>) -> List<&2, Nat>:
  match rows:
    case Nil{}:
      [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n]
    case Con{row, rest}:
      counts.add(row.counts(row), rows.counts(rest))

# a total's counts: questions, gold recalled, gold, characters, unknown
# labels, failed shards, prompt tokens and prompt milliseconds
def total.counts(tot: Sc.Total) -> List<&2, Nat>:
  match tot:
    case Sc.Total{q, hit, gold, chars, unknown, failed, _p50, _mx, pn, pm}:
      [q, hit, gold, chars, unknown, failed, pn, pm]

# LAW: a run's totals count its questions and sum their counts
law total_sums:
  for +rows: List<&2, Sc.Row>
  {total.counts(Sc.Score.total(rows)) == rows.counts(rows) : List<&2, Nat>}

# True when each row's gold recalled is at most its gold
def rows.ok(rows: List<&2, Sc.Row>) -> Bool:
  match rows:
    case Nil{}:
      True{}
    case Con{row, rest}:
      match row:
        case Sc.Row{_id, hit, gold, _chars, _unknown, _failed, _ms, _pn, _pm}:
          Bool.and(Nat.is_le(hit, gold), rows.ok(rest))

# a total's gold recalled
def total.hit(tot: Sc.Total) -> Nat:
  match tot:
    case Sc.Total{_q, hit, _gold, _chars, _unknown, _failed, _p50, _mx, _pn, _pm}:
      hit

# a total's gold
def total.gold(tot: Sc.Total) -> Nat:
  match tot:
    case Sc.Total{_q, _hit, gold, _chars, _unknown, _failed, _p50, _mx, _pn, _pm}:
      gold

# LAW: when no row recalls more than its gold, neither does the run
law total_recall_le:
  for +rows: List<&2, Sc.Row>
  for e: {rows.ok(rows) == True{} : Bool}
  {Nat.is_le(total.hit(Sc.Score.total(rows)), total.gold(Sc.Score.total(rows))) == True{} : Bool}
