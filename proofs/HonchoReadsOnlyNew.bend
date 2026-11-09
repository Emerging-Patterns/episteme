# proofs of laws/HonchoReadsOnlyNew.bend
import Base
import ../src/honcho.bend as H
import ezjson@1.2.0.0/src/value.bend as Value
import ../laws/HonchoReadsOnlyNew.bend as Laws
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/NatArithmetic.bend as M2

# how many messages
def jlen(xs: List<&2, Value.Json>) -> Nat:
  List.length(&2, Value.Json, xs)

# the messages after the first k
def jdrop(xs: List<&2, Value.Json>, k: Nat) -> List<&2, Value.Json>:
  List.drop(&2, Value.Json, xs, k)

# the first k messages
def jtake(xs: List<&2, Value.Json>, k: Nat) -> List<&2, Value.Json>:
  List.take(&2, Value.Json, xs, k)

# xs, then ys
def japp(xs: List<&2, Value.Json>, ys: List<&2, Value.Json>) -> List<&2, Value.Json>:
  List.append(&2, Value.Json, xs, ys)

# a number is at most itself
def nle_refl(n: Nat) -> {Nat.is_le(n, n) == True{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      nle_refl(p)

# at most y is at most y + 1
def nle_succ(x: Nat, y: Nat, h: {Nat.is_le(x, y) == True{} : Bool}) -> {Nat.is_le(x, 1n+y) == True{} : Bool}:
  match x y:
    case 0n _:
      {==}
    case 1n+_p 0n:
      Empty.absurd({Nat.is_le(x, 1n+y) == True{} : Bool}, M1.clash(h))
    case 1n+p 1n+q:
      nle_succ(p, q, h)

# at most b and b at most c is at most c
def nle_trans(
  a: Nat,
  b: Nat,
  c: Nat,
  h1: {Nat.is_le(a, b) == True{} : Bool},
  h2: {Nat.is_le(b, c) == True{} : Bool}
) -> {Nat.is_le(a, c) == True{} : Bool}:
  match a:
    case 0n:
      M1.zero_le(c)
    case 1n+p:
      match b:
        case 0n:
          Empty.absurd({Nat.is_le(1n+p, c) == True{} : Bool}, M1.clash(h1))
        case 1n+q:
          match c:
            case 0n:
              Empty.absurd({Nat.is_le(1n+p, 0n) == True{} : Bool}, M1.clash(h2))
            case 1n+r:
              nle_trans(p, q, r, h1, h2)

# at most b and b below c is below c
def nle_lt(
  a: Nat,
  b: Nat,
  c: Nat,
  h1: {Nat.is_le(a, b) == True{} : Bool},
  h2: {Nat.is_lt(b, c) == True{} : Bool}
) -> {Nat.is_lt(a, c) == True{} : Bool}:
  match a:
    case 0n:
      match b:
        case 0n:
          match c:
            case 0n:
              Empty.absurd({Nat.is_lt(0n, 0n) == True{} : Bool}, M1.clash(h2))
            case 1n+_r:
              {==}
        case 1n+_q:
          match c:
            case 0n:
              Empty.absurd({Nat.is_lt(0n, 0n) == True{} : Bool}, M1.clash(h2))
            case 1n+_r:
              {==}
    case 1n+p:
      match b:
        case 0n:
          Empty.absurd({Nat.is_lt(1n+p, c) == True{} : Bool}, M1.clash(h1))
        case 1n+q:
          match c:
            case 0n:
              Empty.absurd({Nat.is_lt(1n+p, 0n) == True{} : Bool}, M1.clash(h2))
            case 1n+r:
              nle_lt(p, q, r, h1, h2)

# at most b is below b + 1
def nle_lt_succ(a: Nat, b: Nat, h: {Nat.is_le(a, b) == True{} : Bool}) -> {Nat.is_lt(a, 1n+b) == True{} : Bool}:
  match a b:
    case 0n _:
      {==}
    case 1n+_p 0n:
      Empty.absurd({Nat.is_lt(a, 1n+b) == True{} : Bool}, M1.clash(h))
    case 1n+p 1n+q:
      nle_lt_succ(p, q, h)

# nothing is below 0
def nlt_zero(x: Nat, h: {Nat.is_lt(x, 0n) == True{} : Bool}) -> Empty:
  match x:
    case 0n:
      M1.clash(h)
    case 1n+_p:
      M1.clash(h)

# r is at most m + 1 + r
def nle_inv(+m: Nat, +r: Nat) -> {Nat.is_le(r, Nat.add(m, 1n+r)) == True{} : Bool}:
  match m:
    case 0n:
      nle_succ(r, r, nle_refl(r))
    case 1n+p:
      nle_succ(r, Nat.add(p, 1n+r), nle_inv(p, r))

# dropping leaves at most as many
def ldrop_le(
  xs: List<&2, Value.Json>,
  +k: Nat
) -> {Nat.is_le(jlen(jdrop(xs, k)), jlen(xs)) == True{} : Bool}:
  match xs k:
    case Nil{} _:
      {==}
    case Con{+h, +t} 0n:
      nle_refl(jlen(Con{h, t}))
    case Con{_h, +t} 1n+q:
      nle_succ(jlen(jdrop(t, q)),
        jlen(t), ldrop_le(t, q))

# a session's messages from any page are at most all of them
def from_le(
  +all: List<&2, Value.Json>,
  +d: Nat
) -> {Nat.is_le(jlen(H.Honcho.from(all, d)), jlen(all)) == True{} : Bool}:
  match d:
    case 0n:
      nle_refl(jlen(all))
    case 1n+k:
      nle_trans(
        jlen(jdrop(H.Honcho.from(all, k), H.Honcho.size())),
        jlen(H.Honcho.from(all, k)), jlen(all),
        ldrop_le(H.Honcho.from(all, k), H.Honcho.size()), from_le(all, k))

# taking k, then dropping k, puts the list back together
def take_drop(
  xs: List<&2, Value.Json>,
  +k: Nat
) -> {japp(jtake(xs, k), jdrop(xs, k)) == xs : List<&2, Value.Json>}:
  match xs k:
    case Nil{} _:
      {==}
    case Con{_h, _t} 0n:
      {==}
    case Con{+h, t} 1n+q:
      Equal.cong(List<&2, Value.Json>, List<&2, Value.Json>, x => h <> x,
        japp(jtake(t, q), jdrop(t, q)), t,
        take_drop(t, q))

# for s at most k: the first k after the first s, then all after the
# first k, are all after the first s
def page_rest(
  xs: List<&2, Value.Json>,
  k: Nat,
  s: Nat,
  hs: {Nat.is_le(s, k) == True{} : Bool}
) -> {japp(jdrop(jtake(xs, k), s),
    jdrop(xs, k)) == jdrop(xs, s) : List<&2, Value.Json>}:
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      match k:
        case 0n:
          match s:
            case 0n:
              {==}
            case 1n+_p:
              Empty.absurd({japp(jdrop(jtake(Con{h, t}, 0n), s),
                jdrop(Con{h, t}, 0n)) == jdrop(Con{h, t}, s) : List<&2, Value.Json>},
                M1.clash(hs))
        case 1n+q:
          match s:
            case 0n:
              Equal.cong(List<&2, Value.Json>, List<&2, Value.Json>, x => h <> x,
                japp(jtake(t, q), jdrop(t, q)), t,
                take_drop(t, q))
            case 1n+p:
              page_rest(t, q, p, hs)

# a page that is not full is the last: nothing follows it
def short_end(
  xs: List<&2, Value.Json>,
  k: Nat,
  e: {Nat.is_eq(jlen(jtake(xs, k)), k) == False{} : Bool}
) -> {jdrop(xs, k) == [] : List<&2, Value.Json>}:
  match xs k:
    case Nil{} _:
      {==}
    case Con{_h, _t} 0n:
      Empty.absurd({jdrop(xs, k) == [] : List<&2, Value.Json>},
        M1.clash(Equal.sym(Bool, True{}, False{}, e)))
    case Con{_h, t} 1n+q:
      short_end(t, q, e)

# after a full page fewer messages are left than fuel
def full_fuel(
  xs: List<&2, Value.Json>,
  f: Nat,
  e: {H.Honcho.full(jtake(xs, H.Honcho.size())) == True{} : Bool},
  hf: {Nat.is_lt(jlen(xs), 1n+f) == True{} : Bool}
) -> {Nat.is_lt(jlen(jdrop(xs, H.Honcho.size())), f) == True{} : Bool}:
  match xs:
    case Nil{}:
      Empty.absurd({Nat.is_lt(jlen(jdrop(xs, H.Honcho.size())), f) == True{} : Bool},
        M1.clash(e))
    case Con{_h, +t}:
      nle_lt(jlen(jdrop(t, 99n)), jlen(t), f,
        ldrop_le(t, 99n), hf)

# the rest of a read after a full page d: from page d + 1, with fuel f to
# spare, it gives every message from there
def walk_ih(f: Nat, all: List<&2, Value.Json>, d: Nat) -> Type:
  {Nat.is_lt(jlen(H.Honcho.from(all, 1n+d)), f) == True{} : Bool}
    -> {H.Honcho.walk(f, all, H.Place{1n+d, 0n}) == jdrop(H.Honcho.from(all, 1n+d), 0n) : List<&2, Value.Json>}

# a read's step, by whether its page is full, given the rest of the read
def walk_if(
  f: Nat,
  +all: List<&2, Value.Json>,
  +d: Nat,
  +s: Nat,
  b: Bool,
  e: {H.Honcho.full(H.Honcho.page(all, d)) == b : Bool},
  hs: {Nat.is_le(s, H.Honcho.size()) == True{} : Bool},
  hf: {Nat.is_lt(jlen(H.Honcho.from(all, d)), 1n+f) == True{} : Bool},
  ih: walk_ih(f, all, d)
) -> {japp(H.Honcho.fresh(s, H.Honcho.page(all, d)),
    H.Honcho.walk.next(H.Honcho.step.next(b, d), p => H.Honcho.walk(f, all, p)))
    == jdrop(H.Honcho.from(all, d), s) : List<&2, Value.Json>}:
  match b:
    case True{}:
      Equal.trans(List<&2, Value.Json>,
        japp(H.Honcho.fresh(s, H.Honcho.page(all, d)), H.Honcho.walk(f, all, H.Place{1n+d, 0n})),
        japp(H.Honcho.fresh(s, H.Honcho.page(all, d)),
          jdrop(H.Honcho.from(all, d), H.Honcho.size())),
        jdrop(H.Honcho.from(all, d), s),
        Equal.cong(List<&2, Value.Json>, List<&2, Value.Json>,
          x => japp(H.Honcho.fresh(s, H.Honcho.page(all, d)), x),
          H.Honcho.walk(f, all, H.Place{1n+d, 0n}),
          jdrop(H.Honcho.from(all, d), H.Honcho.size()),
          Equal.trans(List<&2, Value.Json>, H.Honcho.walk(f, all, H.Place{1n+d, 0n}),
            jdrop(H.Honcho.from(all, 1n+d), 0n),
            jdrop(H.Honcho.from(all, d), H.Honcho.size()),
            ih(full_fuel(H.Honcho.from(all, d), f, e, hf)),
            M2.drop_zero_l(Value.Json, jdrop(H.Honcho.from(all, d), H.Honcho.size())))),
        page_rest(H.Honcho.from(all, d), H.Honcho.size(), s, hs))
    case False{}:
      Equal.trans(List<&2, Value.Json>,
        japp(H.Honcho.fresh(s, H.Honcho.page(all, d)), []),
        japp(H.Honcho.fresh(s, H.Honcho.page(all, d)),
          jdrop(H.Honcho.from(all, d), H.Honcho.size())),
        jdrop(H.Honcho.from(all, d), s),
        Equal.cong(List<&2, Value.Json>, List<&2, Value.Json>,
          x => japp(H.Honcho.fresh(s, H.Honcho.page(all, d)), x),
          [], jdrop(H.Honcho.from(all, d), H.Honcho.size()),
          Equal.sym(List<&2, Value.Json>, jdrop(H.Honcho.from(all, d), H.Honcho.size()), [],
            short_end(H.Honcho.from(all, d), H.Honcho.size(), e))),
        page_rest(H.Honcho.from(all, d), H.Honcho.size(), s, hs))

# a read from page d past its first s, with fuel to spare, gives every
# message after them
def hon_walk(
  +fuel: Nat,
  +all: List<&2, Value.Json>,
  +d: Nat,
  +s: Nat,
  hs: {Nat.is_le(s, H.Honcho.size()) == True{} : Bool},
  hf: {Nat.is_lt(jlen(H.Honcho.from(all, d)), fuel) == True{} : Bool}
) -> {H.Honcho.walk(fuel, all, H.Place{d, s}) == jdrop(H.Honcho.from(all, d), s) : List<&2, Value.Json>}:
  match fuel:
    case 0n:
      Empty.absurd({H.Honcho.walk(0n, all, H.Place{d, s}) == jdrop(H.Honcho.from(all, d), s) : List<&2, Value.Json>},
        nlt_zero(jlen(H.Honcho.from(all, d)), hf))
    case 1n+f:
      walk_if(f, all, d, s, H.Honcho.full(H.Honcho.page(all, d)), {==}, hs, hf,
        h => hon_walk(f, all, 1n+d, 0n, M1.zero_le(H.Honcho.size()), h))

# a quotient and remainder point at ys in all: after the remainder, from
# the quotient's page on, come ys
def hon.at(all: List<&2, Value.Json>, ys: List<&2, Value.Json>, qr: Nat & Nat) -> Type:
  match qr:
    case (q, r):
      {jdrop(H.Honcho.from(all, q), r) == ys : List<&2, Value.Json>}

# a remainder is at most the page size
def hon.le(qr: Nat & Nat) -> Type:
  match qr:
    case (_q, r):
      {Nat.is_le(r, H.Honcho.size()) == True{} : Bool}

# what is left after the first r is x then rest: after the first r + 1 is
# rest
def drop_next(
  xs: List<&2, Value.Json>,
  +r: Nat,
  -x: Value.Json,
  +rest: List<&2, Value.Json>,
  h: {jdrop(xs, r) == x <> rest : List<&2, Value.Json>}
) -> {jdrop(xs, 1n+r) == rest : List<&2, Value.Json>}:
  Equal.trans(List<&2, Value.Json>, jdrop(xs, 1n+r),
    jdrop(jdrop(xs, r), 1n),
    rest,
    %Equal.sym(Nat, 1n+r, Nat.add(r, 1n), Equal.sym(Nat, Nat.add(r, 1n), 1n+r, M2.add_one(r)))
      : {jdrop(xs, _) == jdrop(jdrop(xs, r), 1n)
        : List<&2, Value.Json>}
    M2.drop_add(Value.Json, xs, r, 1n),
    %Equal.sym(List<&2, Value.Json>, jdrop(xs, r), x <> rest, h)
      : {jdrop(_, 1n) == rest : List<&2, Value.Json>}
    M2.drop_zero_l(Value.Json, rest))

# the invariant after a wrap: r + 1 is the page size
def inv_wrap(
  +r: Nat,
  inv: {Nat.add(0n, 1n+r) == H.Honcho.size() : Nat}
) -> {Nat.add(r, 1n+0n) == H.Honcho.size() : Nat}:
  Equal.trans(Nat, Nat.add(r, 1n), 1n+r, H.Honcho.size(), M2.add_one(r), inv)

# the invariant after a step: m + 1 + r is still the page size
def inv_step(
  +mp: Nat,
  +r: Nat,
  inv: {Nat.add(1n+mp, 1n+r) == H.Honcho.size() : Nat}
) -> {Nat.add(mp, 1n+(1n+r)) == H.Honcho.size() : Nat}:
  Equal.trans(Nat, Nat.add(mp, 1n+(1n+r)), 1n+Nat.add(mp, 1n+r), H.Honcho.size(),
    M2.add_succ_r(mp, 1n+r), inv)

# divmod's walk keeps the place pointing at what follows the messages
# counted
def hon_place(
  xs: List<&2, Value.Json>,
  +ys: List<&2, Value.Json>,
  +all: List<&2, Value.Json>,
  +m: Nat,
  +q: Nat,
  +r: Nat,
  +inv: {Nat.add(m, 1n+r) == H.Honcho.size() : Nat},
  h: {jdrop(H.Honcho.from(all, q), r) == japp(xs, ys) : List<&2, Value.Json>}
) -> hon.at(all, ys, Nat.divmod.go(jlen(xs), m, q, r)):
  match xs:
    case Nil{}:
      h
    case Con{+x, +t}:
      match m:
        case 0n:
          hon_place(t, ys, all, r, 1n+q, 0n, inv_wrap(r, inv),
            Equal.trans(List<&2, Value.Json>,
              jdrop(jdrop(H.Honcho.from(all, q), H.Honcho.size()), 0n),
              jdrop(H.Honcho.from(all, q), H.Honcho.size()),
              japp(t, ys),
              M2.drop_zero_l(Value.Json, jdrop(H.Honcho.from(all, q), H.Honcho.size())),
              %Equal.sym(Nat, H.Honcho.size(), 1n+r, Equal.sym(Nat, 1n+r, H.Honcho.size(), inv))
                : {jdrop(H.Honcho.from(all, q), _) == japp(t, ys)
                  : List<&2, Value.Json>}
              drop_next(H.Honcho.from(all, q), r, x, japp(t, ys), h)))
        case 1n+mp:
          hon_place(t, ys, all, mp, q, 1n+r, inv_step(mp, r, inv),
            drop_next(H.Honcho.from(all, q), r, x, japp(t, ys), h))

# divmod's remainder stays at most the page size
def hon_ple(
  n: Nat,
  +m: Nat,
  -q: Nat,
  +r: Nat,
  +inv: {Nat.add(m, 1n+r) == H.Honcho.size() : Nat}
) -> hon.le(Nat.divmod.go(n, m, q, r)):
  match n:
    case 0n:
      %Equal.sym(Nat, H.Honcho.size(), Nat.add(m, 1n+r), Equal.sym(Nat, Nat.add(m, 1n+r), H.Honcho.size(), inv))
        : {Nat.is_le(r, _) == True{} : Bool}
      nle_inv(m, r)
    case 1n+np:
      match m:
        case 0n:
          hon_ple(np, r, 1n+q, 0n, inv_wrap(r, inv))
        case 1n+mp:
          hon_ple(np, mp, q, 1n+r, inv_step(mp, r, inv))

# a read from the place a quotient and remainder name gives ys
def hon_fin(
  +all: List<&2, Value.Json>,
  -ys: List<&2, Value.Json>,
  qr: Nat & Nat,
  g: hon.at(all, ys, qr),
  gl: hon.le(qr)
) -> {H.Honcho.walk(1n+jlen(all), all, H.Honcho.place.of(qr)) == ys : List<&2, Value.Json>}:
  match qr:
    case (+q, +r):
      Equal.trans(List<&2, Value.Json>,
        H.Honcho.walk(1n+jlen(all), all, H.Place{q, r}),
        jdrop(H.Honcho.from(all, q), r), ys,
        hon_walk(1n+jlen(all), all, q, r, gl,
          nle_lt_succ(jlen(H.Honcho.from(all, q)), jlen(all),
            from_le(all, q))),
        g)

def Laws.read_across(xs, ys):
  hon_fin(japp(xs, ys), ys,
    Nat.divmod(jlen(xs), H.Honcho.size()),
    hon_place(xs, ys, japp(xs, ys), 99n, 0n, 0n, {==},
      M2.drop_zero_l(Value.Json, japp(xs, ys))),
    hon_ple(jlen(xs), 99n, 0n, 0n, {==}))
