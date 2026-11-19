# proofs of laws/BestRankedArePrinted.bend
import Base
import ../src/read.bend as Rd
import ../src/rank.bend as Rk
import ../laws/BestRankedArePrinted.bend as Laws
import ./lemmas/RankCosts.bend as M2

def Laws.better_is_printed(items, budget, per, a, b, ahead, shown):
  M2.le_trans(Rk.Rank.cost(items, a), Rk.Rank.cost(items, b),
    Nat.div(Nat.mul(U32.to_nat(budget), U32.to_nat(per)), 100n),
    M2.cost_mono(items, a, b, ahead), shown)

def Laws.whole_prints_all(items, budget, per, r, whole):
  M2.le_trans(Rk.Rank.cost(items, r), Rk.Rank.total(items),
    Nat.div(Nat.mul(U32.to_nat(budget), U32.to_nat(per)), 100n),
    M2.cost_le_total(items, r), whole)

# --- narrowing ---

# the code's kept labels and ranks are the specification's
law keep_eq:
  for ls: List<&2, String>
  for +rks: List<&2, U32>
  for +items: List<&2, Rk.Item>
  for +budget: U32
  for +per: U32
  {Rk.Rank.keep(ls, rks, items, budget, per)
    == (Laws.kept(ls, rks, items, budget, per), Laws.kept_ranks(ls, rks, items, budget, per))
    : List<&2, String> & List<&2, U32>}

def keep_eq(ls, rks, items, budget, per):
  match ls:
    case Nil{}:
      {==}
    case Con{+l, +rest}:
      %Equal.sym(List<&2, String> & List<&2, U32>,
        Rk.Rank.keep(rest, Rk.Rank.tail(rks), items, budget, per),
        (Laws.kept(rest, Rk.Rank.tail(rks), items, budget, per),
          Laws.kept_ranks(rest, Rk.Rank.tail(rks), items, budget, per)),
        keep_eq(rest, Rk.Rank.tail(rks), items, budget, per))
        : {Rk.Rank.keep.if(
            Rk.Rank.printed(items, budget, per, U32.to_nat(Rk.Rank.head(rks))), l,
            Rk.Rank.head(rks), _)
          == (Laws.kept(l <> rest, rks, items, budget, per),
            Laws.kept_ranks(l <> rest, rks, items, budget, per))
          : List<&2, String> & List<&2, U32>}
      M2.keep_if(Rk.Rank.printed(items, budget, per, U32.to_nat(Rk.Rank.head(rks))), l,
        Rk.Rank.head(rks), Laws.kept(rest, Rk.Rank.tail(rks), items, budget, per),
        Laws.kept_ranks(rest, Rk.Rank.tail(rks), items, budget, per))

def Laws.narrow_keeps_printed(shard, inst, ls, rks, ok, why, pn, pm, cn, ms, items, budget, per):
  Equal.cong(List<&2, String> & List<&2, U32>, Rd.Read,
    k => Rk.Rank.narrow.put(Rd.Read{shard, inst, ls, rks, ok, why, pn, pm, cn, ms}, k),
    Rk.Rank.keep(ls, rks, items, budget, per),
    (Laws.kept(ls, rks, items, budget, per), Laws.kept_ranks(ls, rks, items, budget, per)),
    keep_eq(ls, rks, items, budget, per))

def Laws.narrow_example(_u):
  {==}
