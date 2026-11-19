# A reader that ranked a run may say, beside the labels it names, the rank
# of each: `{"ids": [...], "ranks": [...]}`, the rank of the id in the same
# place, 1 the best of the run. A label with no rank (a reader that does not
# rank, or a reply with fewer ranks than ids) has rank 0, ahead of every
# ranked one. A reader may so name more than `ask` prints: `ask` prints the
# best of what the readers named and keeps the whole of it in run files.
#
# `Rank.items(ss, rs)` is one item per label of every ok read, its rank and
# the characters of the paragraph it names in its shard (none for a label
# the shard does not have). `Rank.cost(items, r)` is the characters of the
# items ranked at or ahead of `r`, and a label of rank `r` is printed,
# `Rank.printed(items, budget, per, r)`, exactly when they fit the budget of
# laws/ExcerptsFitBudget.bend: `Read.fits(Rank.cost(items, r), budget, per)`.
# So the printed labels are the best ranked: when a label is printed, every
# label ranked at or ahead of it is printed too, and when all the items fit,
# every label is printed and the run is whole (`Rank.whole`), which is when
# `ask` writes no run files. Labels of one rank are printed together or not
# at all, so what a reader that does not rank names is printed whole or
# only kept in the files.
#
# `Rank.narrow(rs, items, budget, per)` is the reads with only their printed
# labels: each read keeps, in order, exactly its labels whose rank is
# printed, each with its rank, and is otherwise the same read. `ask` prints
# the excerpts of the narrowed reads and writes the excerpts of the reads as
# they came to the run files.
#
# Proved here: that the better ranked of two labels is printed when the
# other is, that a whole run prints every label, and what a narrowed read
# keeps. Not proved: that the printed labels' paragraphs together fit the
# budget. It follows from the first law (they are the labels ranked at or
# ahead of the worst printed one, whose cost fits), but no law here states
# it over the list.
import Base
import ../src/read.bend as Rd
import ../src/rank.bend as Rk

# the labels of ls, in order, whose rank in the same place of rks (0 past
# their end) is printed
def kept(
  ls: List<&2, String>,
  +rks: List<&2, U32>,
  +items: List<&2, Rk.Item>,
  +budget: U32,
  +per: U32
) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{l, rest}:
      List.filter.put(String, l, kept(rest, Rk.Rank.tail(rks), items, budget, per),
        Rk.Rank.printed(items, budget, per, U32.to_nat(Rk.Rank.head(rks))))

# the ranks of rks, in order, of the labels kept keeps of ls
def kept_ranks(
  ls: List<&2, String>,
  +rks: List<&2, U32>,
  +items: List<&2, Rk.Item>,
  +budget: U32,
  +per: U32
) -> List<&2, U32>:
  match ls:
    case Nil{}:
      []
    case Con{_l, rest}:
      List.filter.put(U32, Rk.Rank.head(rks),
        kept_ranks(rest, Rk.Rank.tail(rks), items, budget, per),
        Rk.Rank.printed(items, budget, per, U32.to_nat(Rk.Rank.head(rks))))

# LAW: when a label is printed, so is every label ranked at or ahead of it
law better_is_printed:
  for +items: List<&2, Rk.Item>
  for +budget: U32
  for +per: U32
  for +a: Nat
  for +b: Nat
  for ahead: {Nat.is_le(a, b) == True{} : Bool}
  for shown: {Rk.Rank.printed(items, budget, per, b) == True{} : Bool}
  {Rk.Rank.printed(items, budget, per, a) == True{} : Bool}

# LAW: a run whose items all fit the budget prints every label
law whole_prints_all:
  for +items: List<&2, Rk.Item>
  for +budget: U32
  for +per: U32
  for +r: Nat
  for whole: {Rk.Rank.whole(items, budget, per) == True{} : Bool}
  {Rk.Rank.printed(items, budget, per, r) == True{} : Bool}

# LAW: a narrowed read keeps exactly its labels whose rank is printed, in
# order, each with its rank, and is otherwise the same read
law narrow_keeps_printed:
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
  for +budget: U32
  for +per: U32
  {Rk.Rank.narrow.one(Rd.Read{shard, inst, ls, rks, ok, why, pn, pm, cn, ms}, items, budget, per)
    == Rd.Read{shard, inst, kept(ls, rks, items, budget, per),
      kept_ranks(ls, rks, items, budget, per), ok, why, pn, pm, cn, ms}
    : Rd.Read}

# LAW: an example: of three labels ranked 2, 1 and 3 whose paragraphs hold
# 6, 5 and 4 characters, a budget of 12 characters prints the two best
law narrow_example:
  for u: Unit
  {Rk.Rank.narrow([Rd.Read{1, "u", ["p1", "p2", "p3"], [2, 1, 3], True{}, "", 0, 0, 0, 0}],
      [Rk.Item{2n, 6n}, Rk.Item{1n, 5n}, Rk.Item{3n, 4n}], 12, 100)
    == [Rd.Read{1, "u", ["p1", "p2"], [2, 1], True{}, "", 0, 0, 0, 0}]
    : List<&2, Rd.Read>}
