# lemmas on ranked items: order on Nat, the cost of the items at or ahead
# of a rank, and a label kept beside its rank
import Base
import ../../src/rank.bend as Rk
import ./BoolFacts.bend as M1

# --- order on Nat ---

# a is at most itself
law le_refl:
  for +a: Nat
  {Nat.is_le(a, a) == True{} : Bool}

def le_refl(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      le_refl(p)

# at most is transitive
law le_trans:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for e1: {Nat.is_le(a, b) == True{} : Bool}
  for e2: {Nat.is_le(b, c) == True{} : Bool}
  {Nat.is_le(a, c) == True{} : Bool}

def le_trans(a, b, c, e1, e2):
  match a:
    case 0n:
      M1.zero_le(c)
    case 1n+p:
      match b:
        case 0n:
          Empty.absurd({Nat.is_le(1n+p, c) == True{} : Bool}, M1.clash(e1))
        case 1n+q:
          match c:
            case 0n:
              Empty.absurd({Nat.is_le(1n+p, 0n) == True{} : Bool}, M1.clash(e2))
            case 1n+r:
              le_trans(p, q, r, e1, e2)

# u is at most y + v when it is at most v
law le_add_l:
  for +u: Nat
  for +v: Nat
  for +y: Nat
  for e: {Nat.is_le(u, v) == True{} : Bool}
  {Nat.is_le(u, Nat.add(y, v)) == True{} : Bool}

def le_add_l(u, v, y, e):
  match y:
    case 0n:
      e
    case 1n+q:
      M1.le_succ(u, Nat.add(q, v), le_add_l(u, v, q, e))

# sums of terms each at most the other's are in that order
law add_le_add:
  for +x: Nat
  for +y: Nat
  for +u: Nat
  for +v: Nat
  for e1: {Nat.is_le(x, y) == True{} : Bool}
  for e2: {Nat.is_le(u, v) == True{} : Bool}
  {Nat.is_le(Nat.add(x, u), Nat.add(y, v)) == True{} : Bool}

def add_le_add(x, y, u, v, e1, e2):
  match x:
    case 0n:
      le_add_l(u, v, y, e2)
    case 1n+p:
      match y:
        case 0n:
          Empty.absurd({Nat.is_le(1n+Nat.add(p, u), v) == True{} : Bool}, M1.clash(e1))
        case 1n+q:
          add_le_add(p, q, u, v, e1, e2)

# --- costs ---

# an item counted when ha costs at most the item counted when hb, when ha
# brings hb
def if_mono(
  ha: Bool,
  hb: Bool,
  +chars: Nat,
  imp: {ha == True{} : Bool} -> {hb == True{} : Bool}
) -> {Nat.is_le(Rk.Rank.cost.if(ha, chars), Rk.Rank.cost.if(hb, chars)) == True{} : Bool}:
  match ha:
    case False{}:
      M1.zero_le(Rk.Rank.cost.if(hb, chars))
    case True{}:
      match hb:
        case True{}:
          le_refl(chars)
        case False{}:
          Empty.absurd({Nat.is_le(chars, 0n) == True{} : Bool}, M1.clash(imp({==})))

# the items at or ahead of the better rank cost at most those at or ahead
# of the other
law cost_mono:
  for items: List<&2, Rk.Item>
  for +a: Nat
  for +b: Nat
  for +e: {Nat.is_le(a, b) == True{} : Bool}
  {Nat.is_le(Rk.Rank.cost(items, a), Rk.Rank.cost(items, b)) == True{} : Bool}

def cost_mono(items, a, b, e):
  match items:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case Rk.Item{+rank, +chars}:
          add_le_add(Rk.Rank.cost.if(Nat.is_le(rank, a), chars),
            Rk.Rank.cost.if(Nat.is_le(rank, b), chars),
            Rk.Rank.cost(rest, a), Rk.Rank.cost(rest, b),
            if_mono(Nat.is_le(rank, a), Nat.is_le(rank, b), chars,
              h => le_trans(rank, a, b, h, e)),
            cost_mono(rest, a, b, e))

# an item counted or not costs at most the item
def if_le(h: Bool, +chars: Nat) -> {Nat.is_le(Rk.Rank.cost.if(h, chars), chars) == True{} : Bool}:
  match h:
    case True{}:
      le_refl(chars)
    case False{}:
      M1.zero_le(chars)

# the items at or ahead of a rank cost at most all the items
law cost_le_total:
  for items: List<&2, Rk.Item>
  for +r: Nat
  {Nat.is_le(Rk.Rank.cost(items, r), Rk.Rank.total(items)) == True{} : Bool}

def cost_le_total(items, r):
  match items:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case Rk.Item{+rank, +chars}:
          add_le_add(Rk.Rank.cost.if(Nat.is_le(rank, r), chars), chars,
            Rk.Rank.cost(rest, r), Rk.Rank.total(rest),
            if_le(Nat.is_le(rank, r), chars), cost_le_total(rest, r))

# --- keeping ---

# a label and its rank kept or not beside kept labels and ranks is each
# list's filter
def keep_if(
  p: Bool,
  l: String,
  rk: U32,
  a: List<&2, String>,
  b: List<&2, U32>
) -> {Rk.Rank.keep.if(p, l, rk, (a, b))
    == (List.filter.put(String, l, a, p), List.filter.put(U32, rk, b, p))
    : List<&2, String> & List<&2, U32>}:
  match p:
    case True{}:
      {==}
    case False{}:
      {==}
