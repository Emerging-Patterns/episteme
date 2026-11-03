# proofs of laws/HitsCountRecalled.bend
import Base
import ../src/excerpt.bend as E
import ../src/score.bend as Sc
import ../laws/HitsCountRecalled.bend as Laws
import ./lemmas/BoolFacts.bend as M1

# a hit added to the rest's count is the specification's pick
def hits_step(
  b: Bool,
  -h: Nat,
  -c: Nat,
  e: {h == c : Nat}
) -> {Nat.add(Sc.Score.one(b), h) == Bool.pick(Nat, b, 1n+c, c) : Nat}:
  match b:
    case True{}:
      Equal.cong(Nat, Nat, y => 1n+y, h, c, e)
    case False{}:
      e

def Laws.hits_count(gs, xs):
  match gs:
    case Nil{}:
      {==}
    case Con{g, +rest}:
      hits_step(E.Excerpt.recalled(g, xs), Sc.Score.hits(rest, xs),
        Laws.recalled.count(rest, xs), Laws.hits_count(rest, xs))

# a hit or none added to at most n is at most n + 1
def hits_le_step(
  b: Bool,
  +h: Nat,
  +n: Nat,
  e: {Nat.is_le(h, n) == True{} : Bool}
) -> {Nat.is_le(Nat.add(Sc.Score.one(b), h), 1n+n) == True{} : Bool}:
  match b:
    case True{}:
      e
    case False{}:
      M1.le_succ(h, n, e)

def Laws.hits_le(gs, xs):
  match gs:
    case Nil{}:
      {==}
    case Con{g, +rest}:
      hits_le_step(E.Excerpt.recalled(g, xs), Sc.Score.hits(rest, xs),
        List.length(&2, E.Gold, rest), Laws.hits_le(rest, xs))
