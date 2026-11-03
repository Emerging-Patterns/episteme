# proofs of laws/SinceDropsOldExcerpts.bend
import Base
import ../src/filter.bend as F
import ../src/excerpt.bend as E
import ../laws/SinceDropsOldExcerpts.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/TakeAndAppend.bend as M2

# a text at or after another by is_ge is so by the specification
def ge_true(
  +a: String,
  +b: String,
  e: {String.is_ge(a, b) == True{} : Bool}
) -> {D1.at_or_after(a, b) == True{} : Bool}:
  %M1.ge_not_lt(a, b) : {_ == True{} : Bool}
  e

def Laws.since_excerpts(since, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %M1.ge_not_lt(D1.ex.ts(x), since) : {List.filter.put(E.Ex, x,
        F.Filter.after.go(rest, since), String.is_ge(E.Excerpt.ts(E.Excerpt.rec(x)), since))
        == List.filter.put(E.Ex, x, Laws.kept_after(rest, since), _) : List<&2, E.Ex>}
      %M2.ts_eq(x) : {List.filter.put(E.Ex, x,
        F.Filter.after.go(rest, since), String.is_ge(E.Excerpt.ts(E.Excerpt.rec(x)), since))
        == List.filter.put(E.Ex, x, Laws.kept_after(rest, since), String.is_ge(_, since))
        : List<&2, E.Ex>}
      %Laws.since_excerpts(since, rest) : {List.filter.put(E.Ex, x,
        F.Filter.after.go(rest, since), String.is_ge(E.Excerpt.ts(E.Excerpt.rec(x)), since))
        == List.filter.put(E.Ex, x, _, String.is_ge(E.Excerpt.ts(E.Excerpt.rec(x)), since))
        : List<&2, E.Ex>}
      {==}

# an excerpt put ahead of excerpts none of which is before since, when
# is_ge keeps it, leaves none before since
def none_put(
  b: Bool,
  +x: E.Ex,
  -r: List<&2, E.Ex>,
  +since: String,
  eb: {String.is_ge(D1.ex.ts(x), since) == b : Bool},
  er: {Laws.none_before(r, since) == True{} : Bool}
) -> {Laws.none_before(List.filter.put(E.Ex, x, r, b), since) == True{} : Bool}:
  match b:
    case True{}:
      M2.and_tt(D1.at_or_after(D1.ex.ts(x), since), Laws.none_before(r, since),
        ge_true(D1.ex.ts(x), since, eb), er)
    case False{}:
      er

def Laws.since_none_old(since, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(x)), D1.ex.ts(x), M2.ts_eq(x))
        : {Laws.none_before(List.filter.put(E.Ex, x, F.Filter.after.go(rest, since),
          String.is_ge(_, since)), since) == True{} : Bool}
      none_put(String.is_ge(D1.ex.ts(x), since), x, F.Filter.after.go(rest, since),
        since, {==}, Laws.since_none_old(since, rest))
