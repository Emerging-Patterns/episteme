# Nat arithmetic, drops, U32 round trips and the scan's state
import Base
import ../../src/para.bend as P
import ../../src/filter.bend as F
import ../../src/excerpt.bend as E
import ../../laws/ParagraphsAreNonBlankRuns.bend as L1
import ../../laws/defs/Specification.bend as D1
import ./BoolFacts.bend as M1
import ./PackingSteps.bend as M2

# --- Nat facts ---

# Zero for 0n, Unit for any other: tells 0n from a successor
def nz(n: Nat) -> Type:
  match n:
    case 0n:
      Empty
    case 1n+_p:
      Unit

# a successor is never 0n
def succ_ne_zero(-p: Nat, e: {1n+p == 0n : Nat}) -> Empty:
  %e : nz(_)
  Unit{}

# one less
def pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p

# adding 0n on the right changes nothing
law add_zero_r:
  for +a: Nat
  {Nat.add(a, 0n) == a : Nat}

def add_zero_r(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, 0n), p, add_zero_r(p))

# a successor on the right comes out
law add_succ_r:
  for +a: Nat
  for +b: Nat
  {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}

def add_succ_r(a, b):
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, 1n+b), 1n+Nat.add(p, b),
        add_succ_r(p, b))

# adding is associative
law add_assoc:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  {Nat.add(Nat.add(a, b), c) == Nat.add(a, Nat.add(b, c)) : Nat}

def add_assoc(a, b, c):
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(Nat.add(p, b), c),
        Nat.add(p, Nat.add(b, c)), add_assoc(p, b, c))

# adding is commutative
law add_comm:
  for +a: Nat
  for +b: Nat
  {Nat.add(a, b) == Nat.add(b, a) : Nat}

def add_comm(a, b):
  match a:
    case 0n:
      Equal.sym(Nat, Nat.add(b, 0n), b, add_zero_r(b))
    case 1n+p:
      Equal.trans(Nat, 1n+Nat.add(p, b), 1n+Nat.add(b, p), Nat.add(b, 1n+p),
        Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, b), Nat.add(b, p),
          add_comm(p, b)),
        Equal.sym(Nat, Nat.add(b, 1n+p), 1n+Nat.add(b, p), add_succ_r(b, p)))

# taking 0n off changes nothing
law sub_zero:
  for a: Nat
  {Nat.sub(a, 0n) == a : Nat}

def sub_zero(a):
  match a:
    case 0n:
      {==}
    case 1n+_p:
      {==}

# a is at most a + d
law le_add:
  for +a: Nat
  for +d: Nat
  {Nat.is_le(a, Nat.add(a, d)) == True{} : Bool}

def le_add(a, d):
  match a:
    case 0n:
      match d:
        case 0n:
          {==}
        case 1n+_q:
          {==}
    case 1n+p:
      le_add(p, d)

# --- U32 round trips ---

# a U32 survives n's round trip through U32
def rt(n: Nat) -> Type:
  {U32.to_nat(U32.from_nat(n)) == n : Nat}

# a word plus one is one more, or it wraps to 0n
def winc(n: Nat, w: Word(n)) -> Type:
  Or({Word.to_nat(n, Word.inc(n, w)) == 1n+Word.to_nat(n, w) : Nat},
    {Word.to_nat(n, Word.inc(n, w)) == 0n : Nat})

# winc, a bit up: twice one more, or still 0n
def winc.up(p: Nat, t: Word(p)) -> Type:
  Or({Nat.double(Word.to_nat(p, Word.inc(p, t)))
      == 1n+1n+Nat.double(Word.to_nat(p, t)) : Nat},
    {Nat.double(Word.to_nat(p, Word.inc(p, t))) == 0n : Nat})

# a carry into the next bit: one more or a wrap below gives the same above
def word_inc.up(-p: Nat, -t: Word(p), r: winc(p, t)) -> winc.up(p, t):
  match r:
    case Inl{e}:
      Inl{Equal.cong(Nat, Nat, x => Nat.double(x),
        Word.to_nat(p, Word.inc(p, t)), 1n+Word.to_nat(p, t), e)}
    case Inr{e}:
      Inr{Equal.cong(Nat, Nat, x => Nat.double(x),
        Word.to_nat(p, Word.inc(p, t)), 0n, e)}

# winc holds of every word
law word_inc:
  for n: Nat
  for w: Word(n)
  winc(n, w)

def word_inc(n, w):
  match n:
    case 0n:
      match w:
        case WNil{}:
          Inr{{==}}
    case 1n+p:
      match w:
        case WCon{False{}, _t}:
          Inl{{==}}
        case WCon{True{}, t}:
          word_inc.up(p, t, word_inc(p, t))

# a U32 plus one is one more, or it wraps to 0n
def uinc(u: U32) -> Type:
  Or({U32.to_nat(U32.inc(u)) == 1n+U32.to_nat(u) : Nat},
    {U32.to_nat(U32.inc(u)) == 0n : Nat})

# uinc holds of every U32
law u32_inc:
  for u: U32
  uinc(u)

def u32_inc(u):
  match u:
    case U32{x}:
      word_inc(32n, x)

# a round trip for a + 1 gives one for a, from how u32_inc went
def rt_down.go(-p: Nat, r: uinc(U32.from_nat(p)), h: rt(1n+p)) -> rt(p):
  match r:
    case Inl{e}:
      Equal.cong(Nat, Nat, x => pred(x), 1n+U32.to_nat(U32.from_nat(p)), 1n+p,
        Equal.trans(Nat, 1n+U32.to_nat(U32.from_nat(p)),
          U32.to_nat(U32.inc(U32.from_nat(p))), 1n+p,
          Equal.sym(Nat, U32.to_nat(U32.inc(U32.from_nat(p))),
            1n+U32.to_nat(U32.from_nat(p)), e), h))
    case Inr{e}:
      Empty.absurd(rt(p), succ_ne_zero(p,
        Equal.trans(Nat, 1n+p, U32.to_nat(U32.inc(U32.from_nat(p))), 0n,
          Equal.sym(Nat, U32.to_nat(U32.inc(U32.from_nat(p))), 1n+p, h), e)))

# a round trip for a + 1 gives one for a
def rt_down(p: Nat, h: rt(1n+p)) -> rt(p):
  rt_down.go(p, u32_inc(U32.from_nat(p)), h)

# move a round trip along an equation
def rt_cast(-a: Nat, -b: Nat, e: {a == b : Nat}, h: rt(a)) -> rt(b):
  %e : rt(_)
  h

# a round trip for m + q gives one for m
def rt_add(+m: Nat, +q: Nat, h: rt(Nat.add(m, q))) -> rt(m):
  match q:
    case 0n:
      rt_cast(Nat.add(m, 0n), m, add_zero_r(m), h)
    case 1n+r:
      rt_add(m, r, rt_down(Nat.add(m, r),
        rt_cast(Nat.add(m, 1n+r), 1n+Nat.add(m, r), add_succ_r(m, r), h)))

# --- String facts ---

# Unit for SNil, Empty for any other: tells SNil from SCon
def sc(s: String) -> Type:
  match s:
    case SNil{}:
      Unit
    case SCon{_h, _t}:
      Empty

# all but the first code point
def tl(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{_h, t}:
      t

# dropping nothing changes nothing
law drop_zero:
  for s: String
  {String.drop(s, 0n) == s : String}

def drop_zero(s):
  match s:
    case SNil{}:
      {==}
    case SCon{_h, _t}:
      {==}

# when dropping k code points leaves c then t, dropping one more leaves t
law drop_step:
  for x: String
  for +k: Nat
  for -c: Char
  for -t: String
  for e: {String.drop(x, k) == SCon{c, t} : String}
  {String.drop(x, 1n+k) == t : String}

def drop_step(x, k, c, t, e):
  match x:
    case SNil{}:
      Empty.absurd({String.drop(SNil{}, 1n+k) == t : String}, (%e : sc(_); Unit{}))
    case SCon{h, y}:
      match k:
        case 0n:
          Equal.trans(String, String.drop(y, 0n), y, t, drop_zero(y),
            Equal.cong(String, String, s => tl(s), SCon{h, y}, SCon{c, t}, e))
        case 1n+j:
          drop_step(y, j, c, t, e)

# x + (1 + y) is never x
def no_loop(x: Nat, +y: Nat, e: {Nat.add(x, 1n+y) == x : Nat}) -> Empty:
  match x:
    case 0n:
      succ_ne_zero(y, e)
    case 1n+p:
      no_loop(p, y, Equal.cong(Nat, Nat, z => pred(z), 1n+Nat.add(p, 1n+y),
        1n+p, e))

# and with False on the right is False
def and_false(a: Bool) -> {Bool.and(a, False{}) == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

# drop_len one code point on
def drop_len.up(
  -p: Nat,
  -t: String,
  x: Exists(Nat, b => {Nat.add(p, 1n+b) == String.length(t) : Nat})
) -> Exists(Nat, b => {Nat.add(1n+p, 1n+b) == 1n+String.length(t) : Nat}):
  match x:
    case (b, e):
      (b, Equal.cong(Nat, Nat, z => 1n+z, Nat.add(p, 1n+b), String.length(t), e))

# what dropping i leaves is not empty, so i is below the length
def drop_len(
  x: String,
  +i: Nat,
  -c: Char,
  -u: String,
  e: {String.drop(x, i) == SCon{c, u} : String}
) -> Exists(Nat, b => {Nat.add(i, 1n+b) == String.length(x) : Nat}):
  match x i:
    case SNil{} _:
      Empty.absurd(Exists(Nat, b => {Nat.add(i, 1n+b) == 0n : Nat}),
        (%e : sc(_); Unit{}))
    case SCon{_h, t} 0n:
      (String.length(t), {==})
    case SCon{_h, t} 1n+p:
      drop_len.up(p, t, drop_len(t, p, c, u, e))

# --- tiles: the paragraphs in order, with whitespace between ---

# from E to F, T is the paragraphs ps in order, with gaps of whitespace
# before, between and after them
def tile(T: String, E: Nat, ps: List<&2, P.Para>, F: Nat) -> Type:
  match ps:
    case Nil{}:
      M1.gap(T, E, F)
    case Con{p, rest}:
      match p:
        case P.Para{_n, s, e, _t}:
          Exists(Nat, ks => Exists(Nat, ke =>
            Pair({s == U32.from_nat(ks) : U32},
            Pair({e == U32.from_nat(ke) : U32},
            Pair(M1.gap(T, E, ks),
            Pair(Exists(Nat, d => {Nat.add(ks, d) == ke : Nat}),
            Pair(Exists(Nat, q => {Nat.add(ke, q) == String.length(T) : Nat}),
              tile(T, ke, rest, F))))))))

# --- the scan's invariant ---

# at m, T has a line feed
def endf(T: String, m: Nat) -> Type:
  Exists(Char, h => Exists(String, x =>
    Pair({String.drop(T, m) == SCon{h, x} : String},
      {D1.nl(h) == True{} : Bool})))

# whitespace from E up to kp, then the text B of a block from kp, which
# holds no blank line, even with a line feed after it
def gapb(T: String, E: Nat, kp: Nat, B: String) -> Type:
  Pair(M1.gap(T, E, kp),
    Pair({D1.blank(D1.line(B)) == False{} : Bool}, {L1.fedok(B) == True{} : Bool}))

# the block, beside a line starting at kl with llen code points so far:
# none, with whitespace from E up to kl; or the text B from kp, ending at a
# line feed just before kl, with whitespace from E up to kp, and room left
# for what the limit leaves
def binv(T: String, cap: Nat, E: Nat, b: P.Block, kl: Nat, llen: Nat) -> Type:
  match b:
    case P.Shut{}:
      M1.gap(T, E, kl)
    case P.Open{psuf, pstart, pend, plen, room}:
      Exists(Nat, kp => Exists(String, B =>
        Pair({pstart == U32.from_nat(kp) : U32},
        Pair({String.drop(T, kp) == psuf : String},
        Pair({pend == U32.from_nat(Nat.add(plen, kp)) : U32},
        Pair({kl == 1n+Nat.add(plen, kp) : Nat},
        Pair({Nat.add(plen, Nat.add(llen, room)) == cap : Nat},
        Pair({psuf == B ++ String.drop(T, Nat.add(plen, kp)) : String},
        Pair({String.length(B) == plen : Nat},
        Pair(gapb(T, E, kp, B), endf(T, Nat.add(plen, kp))))))))))))

# how long the line is so far
def lenof(ln: P.Line) -> Nat:
  match ln:
    case P.Line{_suf, _start, len, _room, _blank}:
      len

# the line, at the scan's offset k with rest left: it starts at kl, its
# text so far is A (no line feed, whitespace while blank), k is llen past
# kl, and the room left on it is what the limit leaves after it
def lfacts(T: String, cap: Nat, k: Nat, kl: Nat, rest: String, ln: P.Line) -> Type:
  match ln:
    case P.Line{lsuf, lstart, llen, lroom, flag}:
      Exists(String, A =>
        Pair({lstart == U32.from_nat(kl) : U32},
        Pair({String.drop(T, kl) == lsuf : String},
        Pair({k == Nat.add(llen, kl) : Nat},
        Pair({Nat.add(llen, lroom) == cap : Nat},
        Pair({lsuf == A ++ rest : String},
        Pair({String.length(A) == llen : Nat},
        Pair({D1.nonl(A) == True{} : Bool}, {D1.blank(A) == flag : Bool}))))))))

# the scan's state, with rest left of T and the paragraphs before it tiled
# up to E: the offset is k, rest is T after k code points, and the line
# and block keep their invariants
def inv(T: String, cap: Nat, E: Nat, rest: String, st: P.Scan) -> Type:
  match st:
    case P.Scan{off, b, ln}:
      Exists(Nat, k => Exists(Nat, kl =>
        Pair({off == U32.from_nat(k) : U32},
        Pair({String.drop(T, k) == rest : String},
        Pair({Nat.add(k, String.length(rest)) == String.length(T) : Nat},
        Pair(lfacts(T, cap, k, kl, rest, ln),
          binv(T, cap, E, b, kl, lenof(ln))))))))

# adding one on the right is a successor
def add_one(+m: Nat) -> {Nat.add(m, 1n) == 1n+m : Nat}:
  Equal.trans(Nat, Nat.add(m, 1n), 1n+Nat.add(m, 0n), 1n+m, add_succ_r(m, 0n),
    Equal.cong(Nat, Nat, x => 1n+x, Nat.add(m, 0n), m, add_zero_r(m)))

# dropping nothing changes nothing
def drop_zero_l(-A: Data, xs: List<&2, A>) -> {List.drop(&2, A, xs, 0n) == xs : List<&2, A>}:
  match xs:
    case Nil{}:
      {==}
    case Con{_h, _t}:
      {==}

# dropping j + k is dropping j, then k
def drop_add(
  -A: Data,
  xs: List<&2, A>,
  j: Nat,
  +k: Nat
) -> {List.drop(&2, A, xs, Nat.add(j, k)) == List.drop(&2, A, List.drop(&2, A, xs, j), k) : List<&2, A>}:
  match xs j:
    case Nil{} 0n:
      {==}
    case Con{+h, +t} 0n:
      {==}
    case Nil{} 1n+_p:
      {==}
    case Con{_h, t} 1n+p:
      drop_add(A, t, p, k)

# xs holds an excerpt, and every one has timestamp t
def block(-t: String, xs: List<&2, E.Ex>) -> Data:
  match xs:
    case Nil{}:
      Empty
    case Con{x, rest}:
      Sigma<&2, &2, {D1.ex.ts(x) == t : String}, _h => M2.at_time(t, rest)>
