# proofs of laws/TotalSumsRows.bend
import Base
import ../src/score.bend as Sc
import ../laws/TotalSumsRows.bend as Laws
import ../laws/defs/ScoreRows.bend as D1
import ./lemmas/BoolFacts.bend as M1

# the median and maximum leave a total's counts alone
def counts_timed(
  tot: Sc.Total,
  -walls: List<&2, Nat>
) -> {Laws.total.counts(Sc.Score.timed(tot, walls)) == Laws.total.counts(tot) : List<&2, Nat>}:
  match tot:
    case Sc.Total{_q, _h, _g, _c, _u, _f, _p, _m, _pn, _pm, _cv, _sp}:
      {==}

# a row added to a total adds its counts
def counts_add(
  row: Sc.Row,
  tot: Sc.Total
) -> {Laws.total.counts(Sc.Score.add(row, tot))
  == Laws.counts.add(Laws.row.counts(row), Laws.total.counts(tot)) : List<&2, Nat>}:
  match row:
    case Sc.Row{_id, _hit, _gold, _chars, _unknown, _failed, _ms, _pn, _pm, _cv, _sp}:
      match tot:
        case Sc.Total{_q, _h, _g, _c, _u, _f, _p, _m, _tpn, _tpm, _cv, _sp}:
          {==}

# the sum's counts are the rows' counts summed
law counts_sum:
  for rows: List<&2, Sc.Row>
  {Laws.total.counts(Sc.Score.sum(rows)) == Laws.rows.counts(rows) : List<&2, Nat>}

def counts_sum(rows):
  match rows:
    case Nil{}:
      {==}
    case Con{+row, +rest}:
      Equal.trans(List<&2, Nat>, Laws.total.counts(Sc.Score.add(row, Sc.Score.sum(rest))),
        Laws.counts.add(Laws.row.counts(row), Laws.total.counts(Sc.Score.sum(rest))),
        Laws.counts.add(Laws.row.counts(row), Laws.rows.counts(rest)),
        counts_add(row, Sc.Score.sum(rest)),
        Equal.cong(List<&2, Nat>, List<&2, Nat>, ys => Laws.counts.add(Laws.row.counts(row), ys),
          Laws.total.counts(Sc.Score.sum(rest)), Laws.rows.counts(rest), counts_sum(rest)))

def Laws.total_sums(rows):
  Equal.trans(List<&2, Nat>,
    Laws.total.counts(Sc.Score.timed(Sc.Score.sum(rows), Sc.Score.walls(rows))),
    Laws.total.counts(Sc.Score.sum(rows)), Laws.rows.counts(rows),
    counts_timed(Sc.Score.sum(rows), Sc.Score.walls(rows)), counts_sum(rows))

# a + c is at most b + d when a is at most b and c at most d
law le_add2:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for e1: {Nat.is_le(a, b) == True{} : Bool}
  for e2: {Nat.is_le(c, d) == True{} : Bool}
  {Nat.is_le(Nat.add(a, c), Nat.add(b, d)) == True{} : Bool}

def le_add2(a, b, c, d, e1, e2):
  match a b:
    case 0n 0n:
      e2
    case 0n 1n+q:
      M1.le_succ(c, Nat.add(q, d), le_add2(0n, q, c, d, M1.zero_le(q), e2))
    case 1n+p 0n:
      Empty.absurd({Nat.is_le(Nat.add(1n+p, c), Nat.add(0n, d)) == True{} : Bool}, M1.clash(e1))
    case 1n+p 1n+q:
      le_add2(p, q, c, d, e1, e2)

# the gold recalled and gold of a total kept by the median and maximum
def hit_gold_timed(
  tot: Sc.Total,
  -walls: List<&2, Nat>
) -> {(Laws.total.hit(Sc.Score.timed(tot, walls)), Laws.total.gold(Sc.Score.timed(tot, walls)))
  == (Laws.total.hit(tot), Laws.total.gold(tot)) : Nat & Nat}:
  match tot:
    case Sc.Total{_q, _h, _g, _c, _u, _f, _p, _m, _pn, _pm, _cv, _sp}:
      {==}

# a row added to a total adds its gold recalled and gold
def hit_gold_add(
  row: Sc.Row,
  tot: Sc.Total
) -> {(Laws.total.hit(Sc.Score.add(row, tot)), Laws.total.gold(Sc.Score.add(row, tot)))
  == (Nat.add(D1.row.hit(row), Laws.total.hit(tot)),
    Nat.add(D1.row.gold(row), Laws.total.gold(tot))) : Nat & Nat}:
  match row:
    case Sc.Row{_id, _hit, _gold, _chars, _unknown, _failed, _ms, _pn, _pm, _cv, _sp}:
      match tot:
        case Sc.Total{_q, _h, _g, _c, _u, _f, _p, _m, _tpn, _tpm, _cv, _sp}:
          {==}

# True when the first is at most the second
def le_pair(pr: Nat & Nat) -> Type:
  match pr:
    case (a, b):
      {Nat.is_le(a, b) == True{} : Bool}

# a row's own ok, from its list's
def row_ok(
  row: Sc.Row,
  -rest: List<&2, Sc.Row>,
  e: {Laws.rows.ok(row <> rest) == True{} : Bool}
) -> {Nat.is_le(D1.row.hit(row), D1.row.gold(row)) == True{} : Bool}:
  match row:
    case Sc.Row{_id, +hit, +gold, _chars, _unknown, _failed, _ms, _pn, _pm, _cv, _sp}:
      M1.and_l(Nat.is_le(hit, gold), Laws.rows.ok(rest), e)

# the rest's ok, from its list's
def rows_rest_ok(
  row: Sc.Row,
  -rest: List<&2, Sc.Row>,
  e: {Laws.rows.ok(row <> rest) == True{} : Bool}
) -> {Laws.rows.ok(rest) == True{} : Bool}:
  match row:
    case Sc.Row{_id, +hit, +gold, _chars, _unknown, _failed, _ms, _pn, _pm, _cv, _sp}:
      M1.and_r(Nat.is_le(hit, gold), Laws.rows.ok(rest), e)

# the sum recalls at most its gold when each row does
law sum_recall_le:
  for rows: List<&2, Sc.Row>
  for +e: {Laws.rows.ok(rows) == True{} : Bool}
  le_pair((Laws.total.hit(Sc.Score.sum(rows)), Laws.total.gold(Sc.Score.sum(rows))))

def sum_recall_le(rows, e):
  match rows:
    case Nil{}:
      {==}
    case Con{+row, +rest}:
      %Equal.sym(Nat & Nat,
        (Laws.total.hit(Sc.Score.add(row, Sc.Score.sum(rest))),
          Laws.total.gold(Sc.Score.add(row, Sc.Score.sum(rest)))),
        (Nat.add(D1.row.hit(row), Laws.total.hit(Sc.Score.sum(rest))),
          Nat.add(D1.row.gold(row), Laws.total.gold(Sc.Score.sum(rest)))),
        hit_gold_add(row, Sc.Score.sum(rest)))
        : le_pair(_)
      le_add2(D1.row.hit(row), D1.row.gold(row),
        Laws.total.hit(Sc.Score.sum(rest)), Laws.total.gold(Sc.Score.sum(rest)),
        row_ok(row, rest, e), sum_recall_le(rest, rows_rest_ok(row, rest, e)))

def Laws.total_recall_le(rows, e):
  %Equal.sym(Nat & Nat,
    (Laws.total.hit(Sc.Score.timed(Sc.Score.sum(rows), Sc.Score.walls(rows))),
      Laws.total.gold(Sc.Score.timed(Sc.Score.sum(rows), Sc.Score.walls(rows)))),
    (Laws.total.hit(Sc.Score.sum(rows)), Laws.total.gold(Sc.Score.sum(rows))),
    hit_gold_timed(Sc.Score.sum(rows), Sc.Score.walls(rows)))
    : le_pair(_)
  sum_recall_le(rows, e)
