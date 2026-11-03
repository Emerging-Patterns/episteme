# Bool facts, and gaps of whitespace
import Base
import ../../src/shard.bend as S
import ../../src/excerpt.bend as E
import ../../src/git.bend as G
import ../../laws/defs/Specification.bend as D1

# --- Bool facts ---

# Unit for True, Empty for False: tells them apart
def bit(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

# False is never True
def clash(e: {False{} == True{} : Bool}) -> Empty:
  %Equal.sym(Bool, False{}, True{}, e) : bit(_)
  Unit{}

# a true and has a true left side
def and_l(a: Bool, -b: Bool, e: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  match a:
    case False{}:
      e
    case True{}:
      {==}

# a true and has a true right side
def and_r(a: Bool, -b: Bool, e: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  match a:
    case False{}:
      Empty.absurd({b == True{} : Bool}, clash(e))
    case True{}:
      e

# --- gaps: stretches of whitespace ---

# from E to S, T is whitespace
def gap(T: String, E: Nat, S: Nat) -> Type:
  Exists(String, G =>
    Pair({String.drop(T, E) == G ++ String.drop(T, S) : String},
    Pair({Nat.add(E, String.length(G)) == S : Nat},
      {D1.blank(G) == True{} : Bool})))

# --- a code point inside a gap is whitespace ---

# the first code point of s, or d
def hd(s: String, d: Char) -> Char:
  match s:
    case SNil{}:
      d
    case SCon{h, _t}:
      h

# nothing is at most any cap
def zero_le(cap: Nat) -> {Nat.is_le(0n, cap) == True{} : Bool}:
  match cap:
    case 0n:
      {==}
    case 1n+_p:
      {==}

# no excerpt of xs has timestamp k
def apart(-k: String, xs: List<&2, E.Ex>) -> Data:
  match xs:
    case Nil{}:
      Unit
    case Con{x, rest}:
      Sigma<&2, &2, {String.eq(D1.ex.ts(x), k) == False{} : Bool}, _h => apart(k, rest)>

# a is at most b + 1 when it is at most b
law le_succ:
  for +a: Nat
  for +b: Nat
  for e: {Nat.is_le(a, b) == True{} : Bool}
  {Nat.is_le(a, 1n+b) == True{} : Bool}

def le_succ(a, b, e):
  match a:
    case 0n:
      {==}
    case 1n+p:
      match b:
        case 0n:
          Empty.absurd({Nat.is_le(1n+p, 1n) == True{} : Bool}, clash(e))
        case 1n+q:
          le_succ(p, q, e)
