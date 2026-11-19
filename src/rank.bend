# episteme/src/rank: which of the labels a run's readers named are printed.
# A reader that ranked the run gives each label its rank, and `ask` prints
# the best ranked that fit the budget and keeps them all in run files
# (laws/BestRankedArePrinted.bend), the next best laid out in pages after the
# printed one (laws/NextBestAreInPages.bend). Pure: no IO.
import Base
import ./para.bend as P
import ./shard.bend as S
import ./excerpt.bend as E
import ./read.bend as Rd

# a named label: its rank (0 when its reader gave none, ahead of every
# ranked one) and the characters of the paragraph it names
type Item is Data:
  Item{rank: Nat, chars: Nat}

# the first rank, or 0 when there is none
def Rank.head(rks: List<&2, U32>) -> U32:
  match rks:
    case Nil{}:
      0
    case Con{rk, _rest}:
      rk

# the ranks after the first, none when there is none
def Rank.tail(rks: List<&2, U32>) -> List<&2, U32>:
  match rks:
    case Nil{}:
      []
    case Con{_rk, rest}:
      rest

# the characters of paragraphs' texts
def Rank.chars.paras(ps: List<&2, P.Para>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          Nat.add(String.length(text), Rank.chars.paras(rest))

# the characters of excerpts' paragraphs' texts
def Rank.chars.exs(xs: List<&2, E.Ex>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{x, rest}:
      Nat.add(Rank.chars.paras(E.Excerpt.paras(x)), Rank.chars.exs(rest))

# the characters of the paragraph a label names in a shard, none for a
# label the shard does not have
def Rank.chars(sh: S.Shard, label: String) -> Nat:
  match sh:
    case S.Shard{_n, items, _sources, _chars, _frozen}:
      Rank.chars.exs(E.Excerpt.items(items, 1, [label]))

# one item per label of ls on the shard, its rank the one in the same
# place of rks, 0 past their end
def Rank.labels(+sh: S.Shard, ls: List<&2, String>, +rks: List<&2, U32>) -> List<&2, Item>:
  match ls:
    case Nil{}:
      []
    case Con{l, rest}:
      Item{U32.to_nat(Rank.head(rks)), Rank.chars(sh, l)}
        <> Rank.labels(sh, rest, Rank.tail(rks))

# the items of the labels ls on the shard when ok, else none
def Rank.read.if(ok: Bool, sh: S.Shard, ls: List<&2, String>, rks: List<&2, U32>) -> List<&2, Item>:
  match ok:
    case True{}:
      Rank.labels(sh, ls, rks)
    case False{}:
      []

# the items of a shard's read: those of its labels when it is ok, none when
# it failed or the shard has no read
def Rank.read(sh: S.Shard, got: Maybe<&2, Rd.Read>) -> List<&2, Item>:
  match got:
    case None{}:
      []
    case Some{rd}:
      match rd:
        case Rd.Read{_shard, _inst, labels, ranks, ok, _why, _pn, _pm, _cn, _ms}:
          Rank.read.if(ok, sh, labels, ranks)

# one item per label of every ok read of the shards, in shard order
def Rank.items(ss: List<&2, S.Shard>, +rs: List<&2, Rd.Read>) -> List<&2, Item>:
  match ss:
    case Nil{}:
      []
    case Con{+sh, rest}:
      List.append(&2, Item, Rank.read(sh, Rd.Read.find(Rd.Read.n(sh), rs)),
        Rank.items(rest, rs))

# chars when hit, else nothing
def Rank.cost.if(hit: Bool, chars: Nat) -> Nat:
  match hit:
    case True{}:
      chars
    case False{}:
      0n

# the characters of the items ranked at or ahead of r
def Rank.cost(items: List<&2, Item>, +r: Nat) -> Nat:
  match items:
    case Nil{}:
      0n
    case Con{it, rest}:
      match it:
        case Item{rank, chars}:
          Nat.add(Rank.cost.if(Nat.is_le(rank, r), chars), Rank.cost(rest, r))

# the characters of all the items
def Rank.total(items: List<&2, Item>) -> Nat:
  match items:
    case Nil{}:
      0n
    case Con{it, rest}:
      match it:
        case Item{_rank, chars}:
          Nat.add(chars, Rank.total(rest))

# whether a label of rank r is printed: the items ranked at or ahead of it
# fit the budget
def Rank.printed(items: List<&2, Item>, budget: U32, per: U32, r: Nat) -> Bool:
  Rd.Read.fits(Rank.cost(items, r), budget, per)

# whether the run is whole: all its items fit the budget, so every label is
# printed
def Rank.whole(items: List<&2, Item>, budget: U32, per: U32) -> Bool:
  Rd.Read.fits(Rank.total(items), budget, per)

# l and rk ahead of the kept labels and ranks when keep
def Rank.keep.if(
  keep: Bool,
  l: String,
  rk: U32,
  more: List<&2, String> & List<&2, U32>
) -> List<&2, String> & List<&2, U32>:
  match keep:
    case True{}:
      (ls, rks) = more
      (l <> ls, rk <> rks)
    case False{}:
      more

# the labels of ls whose rank is printed, in order, beside their ranks
def Rank.keep(
  ls: List<&2, String>,
  +rks: List<&2, U32>,
  +items: List<&2, Item>,
  +budget: U32,
  +per: U32
) -> List<&2, String> & List<&2, U32>:
  match ls:
    case Nil{}:
      ([], [])
    case Con{l, rest}:
      Rank.keep.if(Rank.printed(items, budget, per, U32.to_nat(Rank.head(rks))), l,
        Rank.head(rks), Rank.keep(rest, Rank.tail(rks), items, budget, per))

# a read's labels
def Rank.named(rd: Rd.Read) -> List<&2, String>:
  match rd:
    case Rd.Read{_shard, _inst, labels, _ranks, _ok, _why, _pn, _pm, _cn, _ms}:
      labels

# a read's ranks
def Rank.ranks(rd: Rd.Read) -> List<&2, U32>:
  match rd:
    case Rd.Read{_shard, _inst, _labels, ranks, _ok, _why, _pn, _pm, _cn, _ms}:
      ranks

# the read with the kept labels and ranks for its own
def Rank.narrow.put(rd: Rd.Read, kept: List<&2, String> & List<&2, U32>) -> Rd.Read:
  match rd:
    case Rd.Read{shard, inst, _labels, _ranks, ok, why, pn, pm, cn, ms}:
      (ls, rks) = kept
      Rd.Read{shard, inst, ls, rks, ok, why, pn, pm, cn, ms}

# a read with only its printed labels and their ranks
def Rank.narrow.one(+rd: Rd.Read, items: List<&2, Item>, budget: U32, per: U32) -> Rd.Read:
  Rank.narrow.put(rd, Rank.keep(Rank.named(rd), Rank.ranks(rd), items, budget, per))

# the reads with only their printed labels
def Rank.narrow(rs: List<&2, Rd.Read>, +items: List<&2, Item>, +budget: U32, +per: U32) -> List<&2, Rd.Read>:
  match rs:
    case Nil{}:
      []
    case Con{rd, rest}:
      Rank.narrow.one(rd, items, budget, per) <> Rank.narrow(rest, items, budget, per)

# --- pages ---

# the characters of one budget of budget tokens at per / 100 characters a
# token
def Rank.cap(budget: U32, per: U32) -> Nat:
  Nat.div(Nat.mul(U32.to_nat(budget), U32.to_nat(per)), 100n)

# the characters of k budgets of cap characters
def Rank.caps(k: Nat, +cap: Nat) -> Nat:
  match k:
    case 0n:
      0n
    case 1n+j:
      Nat.add(Rank.caps(j, cap), cap)

# whether a label of rank r is within the first k pages: the items ranked
# at or ahead of it fit k budgets
def Rank.within(items: List<&2, Item>, k: Nat, budget: U32, per: U32, r: Nat) -> Bool:
  Nat.is_le(Rank.cost(items, r), Rank.caps(k, Rank.cap(budget, per)))

# whether a label of rank r is on a page before page j + 1: within the
# first j pages, and never before page 1
def Rank.ahead(items: List<&2, Item>, j: Nat, budget: U32, per: U32, r: Nat) -> Bool:
  match j:
    case 0n:
      False{}
    case 1n+i:
      Rank.within(items, 1n+i, budget, per, r)

# whether a label of rank r is on page k: within the first k pages and on
# none before it; pages count from 1
def Rank.on(+items: List<&2, Item>, k: Nat, +budget: U32, +per: U32, +r: Nat) -> Bool:
  match k:
    case 0n:
      False{}
    case 1n++j:
      Bool.and(Bool.not(Rank.ahead(items, j, budget, per, r)),
        Rank.within(items, 1n+j, budget, per, r))

# whether labels are past page k: all the items do not fit k budgets
def Rank.past(items: List<&2, Item>, k: Nat, budget: U32, per: U32) -> Bool:
  Nat.is_gt(Rank.total(items), Rank.caps(k, Rank.cap(budget, per)))

# the labels of ls whose rank is on page k, in order, beside their ranks
def Rank.page.keep(
  ls: List<&2, String>,
  +rks: List<&2, U32>,
  +items: List<&2, Item>,
  +k: Nat,
  +budget: U32,
  +per: U32
) -> List<&2, String> & List<&2, U32>:
  match ls:
    case Nil{}:
      ([], [])
    case Con{l, rest}:
      Rank.keep.if(Rank.on(items, k, budget, per, U32.to_nat(Rank.head(rks))), l,
        Rank.head(rks), Rank.page.keep(rest, Rank.tail(rks), items, k, budget, per))

# a read with only its labels on page k and their ranks
def Rank.page.one(+rd: Rd.Read, items: List<&2, Item>, k: Nat, budget: U32, per: U32) -> Rd.Read:
  Rank.narrow.put(rd, Rank.page.keep(Rank.named(rd), Rank.ranks(rd), items, k, budget, per))

# the reads with only their labels on page k
def Rank.page(
  rs: List<&2, Rd.Read>,
  +items: List<&2, Item>,
  +k: Nat,
  +budget: U32,
  +per: U32
) -> List<&2, Rd.Read>:
  match rs:
    case Nil{}:
      []
    case Con{rd, rest}:
      Rank.page.one(rd, items, k, budget, per) <> Rank.page(rest, items, k, budget, per)

# page ahead of the pages after it when labels are past the page before
# it, else none
def Rank.rest.if(
  more: Bool,
  page: Unit -> List<&2, Rd.Read>,
  later: Unit -> List<&2, List<&2, Rd.Read>>
) -> List<&2, List<&2, Rd.Read>>:
  match more:
    case False{}:
      []
    case True{}:
      page(Unit{}) <> later(Unit{})

# the reads of page j + 1 and of each page after it, while labels are past
# the page before it, at most fuel pages
def Rank.rest.go(
  fuel: Nat,
  +rs: List<&2, Rd.Read>,
  +items: List<&2, Item>,
  +j: Nat,
  +budget: U32,
  +per: U32
) -> List<&2, List<&2, Rd.Read>>:
  match fuel:
    case 0n:
      []
    case 1n+f:
      Rank.rest.if(Rank.past(items, j, budget, per),
        _u => Rank.page(rs, items, 1n+j, budget, per),
        _u => Rank.rest.go(f, rs, items, 1n+j, budget, per))

# the pages after the first: the reads of page 2, of page 3, ... in order,
# each page's while labels are past the page before it, at most fuel pages
def Rank.rest(
  rs: List<&2, Rd.Read>,
  items: List<&2, Item>,
  fuel: Nat,
  budget: U32,
  per: U32
) -> List<&2, List<&2, Rd.Read>>:
  Rank.rest.go(fuel, rs, items, 1n, budget, per)
