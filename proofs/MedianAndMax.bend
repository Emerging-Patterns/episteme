# proofs of laws/MedianAndMax.bend
import Base
import ../src/score.bend as Sc
import ../laws/MedianAndMax.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ./lemmas/BoolFacts.bend as M1

# at least is transitive
law ge_trans:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for e1: {Nat.is_ge(a, b) == True{} : Bool}
  for e2: {Nat.is_ge(b, c) == True{} : Bool}
  {Nat.is_ge(a, c) == True{} : Bool}

def ge_trans(a, b, c, e1, e2):
  match a b c:
    case 0n _ 0n:
      {==}
    case 1n+_p _ 0n:
      {==}
    case aa 0n 1n+rr:
      Empty.absurd({Nat.is_ge(aa, 1n+rr) == True{} : Bool}, M1.clash(e2))
    case 0n 1n+_q 1n+rr:
      Empty.absurd({Nat.is_ge(0n, 1n+rr) == True{} : Bool}, M1.clash(e1))
    case 1n+p 1n+q 1n+r:
      ge_trans(p, q, r, e1, e2)

def Laws.max_ge(ns, x, h):
  match ns:
    case Nil{}:
      Empty.absurd({Nat.is_ge(0n, x) == True{} : Bool}, h)
    case Con{+n, +rest}:
      match h:
        case Inl{e}:
          %Equal.sym(Nat, x, n, e) : {Nat.is_ge(Nat.max(n, Sc.Score.max(rest)), _) == True{} : Bool}
          Nat.max_ge_l(n, Sc.Score.max(rest))
        case Inr{el}:
          ge_trans(Nat.max(n, Sc.Score.max(rest)), Sc.Score.max(rest), x,
            Nat.max_ge_r(n, Sc.Score.max(rest)), Laws.max_ge(rest, x, el))

# x is among the list it is slotted into, by how it compared to y
def slot_has.at(
  b: Bool,
  -x: Nat,
  -y: Nat,
  -rest: List<&2, Nat>,
  ih: D1.Elem(Nat, x, Sc.Score.slot(x, rest))
) -> D1.Elem(Nat, x, Sc.Score.slot.if(b, x, y, rest, _u => Sc.Score.slot(x, rest))):
  match b:
    case True{}:
      Inl{{==}}
    case False{}:
      Inr{ih}

# x is among the list it is slotted into
law slot_has:
  for +x: Nat
  for ys: List<&2, Nat>
  D1.Elem(Nat, x, Sc.Score.slot(x, ys))

def slot_has(x, ys):
  match ys:
    case Nil{}:
      Inl{{==}}
    case Con{+y, +rest}:
      slot_has.at(Nat.is_le(x, y), x, y, rest, slot_has(x, rest))

# what is among a list with y put second was among it
def slot_skip(
  -z: Nat,
  -x: Nat,
  -y: Nat,
  -rest: List<&2, Nat>,
  h: D1.Elem(Nat, z, x <> rest)
) -> D1.Elem(Nat, z, x <> y <> rest):
  match h:
    case Inl{e}:
      Inl{e}
    case Inr{el}:
      Inr{Inr{el}}

# what is among a slot's list by how x compared to y was among it or is x
def slot_elem.at(
  b: Bool,
  -z: Nat,
  -x: Nat,
  -y: Nat,
  -rest: List<&2, Nat>,
  ih: D1.Elem(Nat, z, Sc.Score.slot(x, rest)) -> D1.Elem(Nat, z, x <> rest),
  h: D1.Elem(Nat, z, Sc.Score.slot.if(b, x, y, rest, _u => Sc.Score.slot(x, rest)))
) -> D1.Elem(Nat, z, x <> y <> rest):
  match b:
    case True{}:
      h
    case False{}:
      match h:
        case Inl{e}:
          Inr{Inl{e}}
        case Inr{el}:
          slot_skip(z, x, y, rest, ih(el))

# what is among a list after x is slotted in is x or was among it
law slot_elem:
  for -z: Nat
  for +x: Nat
  for ys: List<&2, Nat>
  for h: D1.Elem(Nat, z, Sc.Score.slot(x, ys))
  D1.Elem(Nat, z, x <> ys)

def slot_elem(z, x, ys, h):
  match ys:
    case Nil{}:
      h
    case Con{+y, +rest}:
      slot_elem.at(Nat.is_le(x, y), z, x, y, rest, hh => slot_elem(z, x, rest, hh), h)

# what is after x among a list moved along a map of the rest
def nat_tail(
  -z: Nat,
  -x: Nat,
  -a: List<&2, Nat>,
  -b: List<&2, Nat>,
  f: D1.Elem(Nat, z, a) -> D1.Elem(Nat, z, b),
  h: D1.Elem(Nat, z, x <> a)
) -> D1.Elem(Nat, z, x <> b):
  match h:
    case Inl{e}:
      Inl{e}
    case Inr{el}:
      Inr{f(el)}

# what is among sorted times was among them
law nat_sort_elem:
  for -z: Nat
  for ys: List<&2, Nat>
  for h: D1.Elem(Nat, z, Sc.Score.sort(ys))
  D1.Elem(Nat, z, ys)

def nat_sort_elem(z, ys, h):
  match ys:
    case Nil{}:
      h
    case Con{+x, +rest}:
      nat_tail(z, x, Sc.Score.sort(rest), rest, hh => nat_sort_elem(z, rest, hh),
        slot_elem(z, x, Sc.Score.sort(rest), h))

# the element at an index of a list is among it
law at_elem:
  for rest: List<&2, Nat>
  for +head: Nat
  for idx: Nat
  D1.Elem(Nat, Sc.Score.at(rest, head, idx), head <> rest)

def at_elem(rest, _head, idx):
  match rest:
    case Nil{}:
      Inl{{==}}
    case Con{+next, +more}:
      match idx:
        case 0n:
          Inl{{==}}
        case 1n+j:
          Inr{at_elem(more, next, j)}

# the median of a list with an element is among it
law mid_elem:
  for zs: List<&2, Nat>
  for -z: Nat
  for h: D1.Elem(Nat, z, zs)
  D1.Elem(Nat, Sc.Score.mid(zs), zs)

def mid_elem(zs, _z, h):
  match zs:
    case Nil{}:
      Empty.absurd(D1.Elem(Nat, 0n, []), h)
    case Con{+x, +rest}:
      at_elem(rest, x, Nat.div(List.length(&2, Nat, rest), 2n))

def Laws.p50_elem(x, rest):
  nat_sort_elem(Sc.Score.p50(x <> rest), x <> rest,
    mid_elem(Sc.Score.sort(x <> rest), x, slot_has(x, Sc.Score.sort(rest))))

def Laws.p50_le_max(x, rest):
  Laws.max_ge(x <> rest, Sc.Score.p50(x <> rest), Laws.p50_elem(x, rest))
