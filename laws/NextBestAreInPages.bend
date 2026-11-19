# What a run's readers named beyond what `ask` prints is laid out in pages,
# best ranked first, so that the next best can be read without the whole of
# it. Page 1 is what `ask` prints (laws/BestRankedArePrinted.bend), page 2
# what one more budget holds after it, and so on; `ask` writes each page
# after the first to a run file of its own beside the files of the sources.
#
# `Rank.cap(budget, per)` is the characters of the budget of
# laws/ExcerptsFitBudget.bend and `Rank.caps(k, cap)` those of `k` such
# budgets. A label of rank `r` is within the first `k` pages,
# `Rank.within(items, k, budget, per, r)`, exactly when the items ranked at
# or ahead of it fit `k` budgets, and it is on page `k`,
# `Rank.on(items, k, budget, per, r)`, when it is within the first `k` pages
# and not within the first `k - 1`; no label is on page 0. So a label is on
# page 1 exactly when it is printed, no label is on two pages, and a label
# ranked at or ahead of one on page `k` is on page `k` or an earlier one.
# Labels of one rank are on one page together, as they are printed together.
#
# `Rank.past(items, k, budget, per)` says whether labels are past page `k`:
# all the items do not fit `k` budgets. When none is, every label is within
# the first `k` pages. `Rank.page(rs, items, k, budget, per)` is the reads
# with only their labels on page `k`: each read keeps, in order, exactly
# those labels, each with its rank, and is otherwise the same read.
# `Rank.rest(rs, items, fuel, budget, per)` is the pages after the first in
# order, page 2 then page 3 and on, each as long as labels are past the page
# before it and at most `fuel` of them; what is past the last of those is
# only in the files of the sources.
#
# Proved here: the four facts above about which page a label is on, and what
# a page's read keeps. Not proved: that the paragraphs of one page fit one
# budget. A page holds what the budget ending it fits and the pages before
# did not, so it is at most one budget and the labels of one rank over it;
# no law here states it over the list. `Rank.rest` is checked by the example.
# also rests on: laws/BestRankedArePrinted.bend
import Base
import ../src/read.bend as Rd
import ../src/rank.bend as Rk

# the labels of ls, in order, whose rank in the same place of rks (0 past
# their end) is on page k
def paged(
  ls: List<&2, String>,
  +rks: List<&2, U32>,
  +items: List<&2, Rk.Item>,
  +k: Nat,
  +budget: U32,
  +per: U32
) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{l, rest}:
      List.filter.put(String, l, paged(rest, Rk.Rank.tail(rks), items, k, budget, per),
        Rk.Rank.on(items, k, budget, per, U32.to_nat(Rk.Rank.head(rks))))

# the ranks of rks, in order, of the labels paged keeps of ls
def paged_ranks(
  ls: List<&2, String>,
  +rks: List<&2, U32>,
  +items: List<&2, Rk.Item>,
  +k: Nat,
  +budget: U32,
  +per: U32
) -> List<&2, U32>:
  match ls:
    case Nil{}:
      []
    case Con{_l, rest}:
      List.filter.put(U32, Rk.Rank.head(rks),
        paged_ranks(rest, Rk.Rank.tail(rks), items, k, budget, per),
        Rk.Rank.on(items, k, budget, per, U32.to_nat(Rk.Rank.head(rks))))

# LAW: a label is on page 1 exactly when it is printed
law first_page_is_printed:
  for +items: List<&2, Rk.Item>
  for +budget: U32
  for +per: U32
  for +r: Nat
  {Rk.Rank.on(items, 1n, budget, per, r) == Rk.Rank.printed(items, budget, per, r) : Bool}

# LAW: a label on a page is on no later page
law on_one_page:
  for +items: List<&2, Rk.Item>
  for +budget: U32
  for +per: U32
  for +r: Nat
  for +j: Nat
  for +k: Nat
  for later: {Nat.is_le(1n+j, k) == True{} : Bool}
  for there: {Rk.Rank.on(items, j, budget, per, r) == True{} : Bool}
  {Rk.Rank.on(items, k, budget, per, r) == False{} : Bool}

# LAW: a label ranked at or ahead of one on page k is within the first k
# pages
law better_is_no_later:
  for +items: List<&2, Rk.Item>
  for +budget: U32
  for +per: U32
  for +a: Nat
  for +b: Nat
  for +k: Nat
  for ahead: {Nat.is_le(a, b) == True{} : Bool}
  for there: {Rk.Rank.on(items, k, budget, per, b) == True{} : Bool}
  {Rk.Rank.within(items, k, budget, per, a) == True{} : Bool}

# LAW: when no label is past page k, every label is within the first k pages
law none_past_the_last:
  for +items: List<&2, Rk.Item>
  for +budget: U32
  for +per: U32
  for +k: Nat
  for +r: Nat
  for last: {Rk.Rank.past(items, k, budget, per) == False{} : Bool}
  {Rk.Rank.within(items, k, budget, per, r) == True{} : Bool}

# LAW: a page's read keeps exactly its labels whose rank is on the page, in
# order, each with its rank, and is otherwise the same read
law page_keeps_its_labels:
  for shard: U32
  for inst: String
  for +ls: List<&2, String>
  for +rks: List<&2, U32>
  for ok: Bool
  for why: String
  for pn: U32
  for pm: U32
  for cn: U32
  for ms: U32
  for +items: List<&2, Rk.Item>
  for +k: Nat
  for +budget: U32
  for +per: U32
  {Rk.Rank.page.one(Rd.Read{shard, inst, ls, rks, ok, why, pn, pm, cn, ms}, items, k, budget, per)
    == Rd.Read{shard, inst, paged(ls, rks, items, k, budget, per),
      paged_ranks(ls, rks, items, k, budget, per), ok, why, pn, pm, cn, ms}
    : Rd.Read}

# LAW: an example: of three labels ranked 2, 1 and 3 whose paragraphs hold
# 6, 5 and 4 characters, a budget of 6 characters prints the best, and the
# pages after it hold the second, then the third
law rest_example:
  for u: Unit
  {Rk.Rank.rest([Rd.Read{1, "u", ["p1", "p2", "p3"], [2, 1, 3], True{}, "", 0, 0, 0, 0}],
      [Rk.Item{2n, 6n}, Rk.Item{1n, 5n}, Rk.Item{3n, 4n}], 99n, 6, 100)
    == [[Rd.Read{1, "u", ["p1"], [2], True{}, "", 0, 0, 0, 0}],
      [Rd.Read{1, "u", ["p3"], [3], True{}, "", 0, 0, 0, 0}]]
    : List<&2, List<&2, Rd.Read>>}
