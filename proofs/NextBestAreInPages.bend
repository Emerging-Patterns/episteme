# proofs of laws/NextBestAreInPages.bend
import Base
import ../src/read.bend as Rd
import ../src/rank.bend as Rk
import ../laws/NextBestAreInPages.bend as Laws
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/RankCosts.bend as M2

def Laws.first_page_is_printed(_items, _budget, _per, _r):
  {==}

# --- budgets ---

# fewer budgets hold at most as many characters
law caps_mono:
  for +a: Nat
  for +b: Nat
  for +cap: Nat
  for e: {Nat.is_le(a, b) == True{} : Bool}
  {Nat.is_le(Rk.Rank.caps(a, cap), Rk.Rank.caps(b, cap)) == True{} : Bool}

def caps_mono(a, b, cap, e):
  match a:
    case 0n:
      M1.zero_le(Rk.Rank.caps(b, cap))
    case 1n+p:
      match b:
        case 0n:
          Empty.absurd({Nat.is_le(Nat.add(Rk.Rank.caps(p, cap), cap), 0n) == True{} : Bool}, M1.clash(e))
        case 1n+q:
          M2.add_le_add(Rk.Rank.caps(p, cap), Rk.Rank.caps(q, cap), cap, cap,
            caps_mono(p, q, cap, e), M2.le_refl(cap))

# a is at most b when it is not over it
law le_of_not_gt:
  for +a: Nat
  for +b: Nat
  for e: {Nat.is_gt(a, b) == False{} : Bool}
  {Nat.is_le(a, b) == True{} : Bool}

def le_of_not_gt(a, b, e):
  match a:
    case 0n:
      M1.zero_le(b)
    case 1n+p:
      match b:
        case 0n:
          Empty.absurd({Nat.is_le(1n+p, 0n) == True{} : Bool},
            M1.clash(Equal.sym(Bool, True{}, False{}, e)))
        case 1n+q:
          le_of_not_gt(p, q, e)

# --- pages ---

def Laws.on_one_page(items, budget, per, r, j, k, later, there):
  match j:
    case 0n:
      Empty.absurd({Rk.Rank.on(items, k, budget, per, r) == False{} : Bool}, M1.clash(there))
    case 1n+jp:
      match k:
        case 0n:
          {==}
        case 1n:
          Empty.absurd({Rk.Rank.on(items, 1n, budget, per, r) == False{} : Bool}, M1.clash(later))
        case 2n+i:
          %Equal.sym(Bool, Rk.Rank.within(items, 1n+i, budget, per, r), True{},
            M2.le_trans(Rk.Rank.cost(items, r),
              Rk.Rank.caps(1n+jp, Rk.Rank.cap(budget, per)),
              Rk.Rank.caps(1n+i, Rk.Rank.cap(budget, per)),
              M1.and_r(Bool.not(Rk.Rank.ahead(items, jp, budget, per, r)),
                Rk.Rank.within(items, 1n+jp, budget, per, r), there),
              caps_mono(1n+jp, 1n+i, Rk.Rank.cap(budget, per), later)))
            : {Bool.and(Bool.not(_), Rk.Rank.within(items, 2n+i, budget, per, r)) == False{} : Bool}
          {==}

def Laws.better_is_no_later(items, budget, per, a, b, k, ahead, there):
  match k:
    case 0n:
      Empty.absurd({Rk.Rank.within(items, 0n, budget, per, a) == True{} : Bool}, M1.clash(there))
    case 1n+j:
      M2.le_trans(Rk.Rank.cost(items, a), Rk.Rank.cost(items, b),
        Rk.Rank.caps(1n+j, Rk.Rank.cap(budget, per)),
        M2.cost_mono(items, a, b, ahead),
        M1.and_r(Bool.not(Rk.Rank.ahead(items, j, budget, per, b)),
          Rk.Rank.within(items, 1n+j, budget, per, b), there))

def Laws.none_past_the_last(items, budget, per, k, r, last):
  M2.le_trans(Rk.Rank.cost(items, r), Rk.Rank.total(items),
    Rk.Rank.caps(k, Rk.Rank.cap(budget, per)),
    M2.cost_le_total(items, r),
    le_of_not_gt(Rk.Rank.total(items), Rk.Rank.caps(k, Rk.Rank.cap(budget, per)), last))

# --- a page's read ---

# the code's page labels and ranks are the specification's
law page_keep_eq:
  for ls: List<&2, String>
  for +rks: List<&2, U32>
  for +items: List<&2, Rk.Item>
  for +k: Nat
  for +budget: U32
  for +per: U32
  {Rk.Rank.page.keep(ls, rks, items, k, budget, per)
    == (Laws.paged(ls, rks, items, k, budget, per), Laws.paged_ranks(ls, rks, items, k, budget, per))
    : List<&2, String> & List<&2, U32>}

def page_keep_eq(ls, rks, items, k, budget, per):
  match ls:
    case Nil{}:
      {==}
    case Con{+l, +rest}:
      %Equal.sym(List<&2, String> & List<&2, U32>,
        Rk.Rank.page.keep(rest, Rk.Rank.tail(rks), items, k, budget, per),
        (Laws.paged(rest, Rk.Rank.tail(rks), items, k, budget, per),
          Laws.paged_ranks(rest, Rk.Rank.tail(rks), items, k, budget, per)),
        page_keep_eq(rest, Rk.Rank.tail(rks), items, k, budget, per))
        : {Rk.Rank.keep.if(
            Rk.Rank.on(items, k, budget, per, U32.to_nat(Rk.Rank.head(rks))), l,
            Rk.Rank.head(rks), _)
          == (Laws.paged(l <> rest, rks, items, k, budget, per),
            Laws.paged_ranks(l <> rest, rks, items, k, budget, per))
          : List<&2, String> & List<&2, U32>}
      M2.keep_if(Rk.Rank.on(items, k, budget, per, U32.to_nat(Rk.Rank.head(rks))), l,
        Rk.Rank.head(rks), Laws.paged(rest, Rk.Rank.tail(rks), items, k, budget, per),
        Laws.paged_ranks(rest, Rk.Rank.tail(rks), items, k, budget, per))

def Laws.page_keeps_its_labels(shard, inst, ls, rks, ok, why, pn, pm, cn, ms, items, k, budget, per):
  Equal.cong(List<&2, String> & List<&2, U32>, Rd.Read,
    kept => Rk.Rank.narrow.put(Rd.Read{shard, inst, ls, rks, ok, why, pn, pm, cn, ms}, kept),
    Rk.Rank.page.keep(ls, rks, items, k, budget, per),
    (Laws.paged(ls, rks, items, k, budget, per), Laws.paged_ranks(ls, rks, items, k, budget, per)),
    page_keep_eq(ls, rks, items, k, budget, per))

def Laws.rest_example(_u):
  {==}
