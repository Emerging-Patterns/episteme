# membership along equal lists, and the offsets paragraphs hold
import Base
import ../../src/para.bend as P
import ../../src/excerpt.bend as E
import ../../laws/defs/ListMembership.bend as D1
import ../../laws/defs/Specification.bend as D2

# p holds offset i: from ks to ke, ks <= i < ke, ke inside T
def hitn(T: String, i: Nat, p: P.Para) -> Type:
  match p:
    case P.Para{_n, s, e, _t}:
      Exists(Nat, ks => Exists(Nat, ke =>
        Pair({s == U32.from_nat(ks) : U32},
        Pair({e == U32.from_nat(ke) : U32},
        Pair(Exists(Nat, a => {Nat.add(ks, a) == i : Nat}),
        Pair(Exists(Nat, b => {Nat.add(i, 1n+b) == ke : Nat}),
          Exists(Nat, q => {Nat.add(ke, q) == String.length(T) : Nat})))))))

# some paragraph of ps holds offset i
def hits(T: String, i: Nat, ps: List<&2, P.Para>) -> Type:
  Exists(P.Para, p => Pair(D2.In(p, ps), hitn(T, i, p)))

# --- list facts ---

# appending nothing changes nothing
def lapp_nil(-A: Data, xs: List<&2, A>) -> {List.append(&2, A, xs, []) == xs : List<&2, A>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, t}:
      Equal.cong(List<&2, A>, List<&2, A>, x => h <> x, List.append(&2, A, t, []),
        t, lapp_nil(A, t))

# a lazy or is an or
def any_if_or(
  b: Bool,
  -x: Bool,
  -y: Bool,
  e: {x == y : Bool}
) -> {List.any.if(_u => x, b) == Bool.or(b, y) : Bool}:
  match b:
    case False{}:
      e
    case True{}:
      {==}

# the code's label test is the specification's
law named_mem:
  for +text: String
  for ls: List<&2, String>
  {E.Excerpt.named(text, ls) == D2.mem(text, ls) : Bool}

def named_mem(text, ls):
  match ls:
    case Nil{}:
      {==}
    case Con{+head, rest}:
      any_if_or(String.eq(text, head), E.Excerpt.named(text, rest),
        D2.mem(text, rest), named_mem(text, rest))

# move membership along an equation of lists
def elem_cast(
  -A: Data,
  -x: A,
  -xs: List<&2, A>,
  -ys: List<&2, A>,
  e: {xs == ys : List<&2, A>},
  h: D1.Elem(A, x, xs)
) -> D1.Elem(A, x, ys):
  %e : D1.Elem(A, x, _)
  h
