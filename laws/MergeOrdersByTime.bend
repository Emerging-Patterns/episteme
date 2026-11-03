# `Excerpt.merge` output is ordered by `ts`; for every `ts`, its records of
# that `ts` are, in order, those of the first excerpt of each record id in the
# input with that `ts` (so each record once, equal `ts` in shard order); every
# excerpt's paragraph numbers ascend strictly (each paragraph once); a record
# id and paragraph number are in the output exactly when they are in the
# input; and every output paragraph is a paragraph of an input excerpt of the
# same record id.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/excerpt.bend as E
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2

# True when the timestamps of xs never fall, from prev on
def rising.from(xs: List<&2, E.Ex>, +prev: String) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+x, tail}:
      Bool.and(String.is_le(prev, D2.ex.ts(x)), rising.from(tail, D2.ex.ts(x)))

# True when the timestamps of xs never fall
def rising(xs: List<&2, E.Ex>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+x, tail}:
      rising.from(tail, D2.ex.ts(x))

# LAW: merged excerpts are in timestamp order
law merge_sorted:
  for xs: List<&2, List<&2, E.Ex>>
  {rising(E.Excerpt.merge(xs)) == True{} : Bool}

# cur ahead of rest unless its record id was seen
def first.if(seen: Bool, cur: E.Ex, rest: List<&2, E.Ex>) -> List<&2, E.Ex>:
  match seen:
    case True{}:
      rest
    case False{}:
      cur <> rest

# the first excerpt of each record id in xs not among seen, in order
def firsts(xs: List<&2, E.Ex>, +seen: List<&2, String>) -> List<&2, E.Ex>:
  match xs:
    case Nil{}:
      []
    case Con{+x, tail}:
      first.if(D2.mem(D2.rec.id(D2.ex.rec(x)), seen), x,
        firsts(tail, D2.rec.id(D2.ex.rec(x)) <> seen))

# LAW: for every timestamp, the merged records with it are, in order, the
# records of the first excerpt of each record id among the input excerpts
# with it: each record once, and records of equal timestamp in shard order
law merge_stable:
  for xs: List<&2, List<&2, E.Ex>>
  for +t: String
  {D2.recs(D2.only(t, E.Excerpt.merge(xs)))
    == D2.recs(firsts(D2.only(t, List.concat(&2, E.Ex, xs)), []))
    : List<&2, R.Record>}

# True when each paragraph's number is above the one before, from prev on
def climbing.from(ps: List<&2, P.Para>, +prev: U32) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{+p, tail}:
      Bool.and(U32.is_lt(prev, D2.para.n(p)), climbing.from(tail, D2.para.n(p)))

# True when each paragraph's number is above the one before
def climbing(ps: List<&2, P.Para>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{+p, tail}:
      climbing.from(tail, D2.para.n(p))

# LAW: every merged excerpt's paragraph numbers ascend strictly: each
# paragraph once, in order
law merge_paras:
  for xs: List<&2, List<&2, E.Ex>>
  for x: E.Ex
  for hx: D1.Elem(E.Ex, x, E.Excerpt.merge(xs))
  {climbing(D2.ex.paras(x)) == True{} : Bool}

# LAW: a record id and paragraph number are merged exactly when some input
# excerpt holds them: merging loses and invents no paragraph
law merge_holds:
  for xs: List<&2, List<&2, E.Ex>>
  for +id: String
  for +n: U32
  {D2.holds(id, n, E.Excerpt.merge(xs))
    == D2.holds(id, n, List.concat(&2, E.Ex, xs)) : Bool}

# LAW: every merged paragraph is a paragraph of an input excerpt of the same
# record id: merging keeps the shard's text
law merge_verbatim:
  for xs: List<&2, List<&2, E.Ex>>
  for x: E.Ex
  for hx: D1.Elem(E.Ex, x, E.Excerpt.merge(xs))
  for q: P.Para
  for hq: D1.Elem(P.Para, q, D2.ex.paras(x))
  exs y: E.Ex
  Pair(D1.Elem(E.Ex, y, List.concat(&2, E.Ex, xs)),
    Pair({D2.rec.id(D2.ex.rec(y)) == D2.rec.id(D2.ex.rec(x)) : String},
      D1.Elem(P.Para, q, D2.ex.paras(y))))
