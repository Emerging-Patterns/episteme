# packing step by step, and what holds of every paragraph and excerpt
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../src/excerpt.bend as E
import ../../laws/ParagraphsAreNonBlankRuns.bend as L1
import ../../laws/defs/Specification.bend as D1

# --- what holds of every paragraph the scan emits ---

# the run ends at m: at the end of T, or at a line feed and a blank line
def rend(T: String, m: Nat) -> Type:
  Or({String.drop(T, m) == SNil{} : String},
    Exists(Char, h => Exists(String, r =>
      Pair({String.drop(T, m) == SCon{h, r} : String},
      Pair({D1.nl(h) == True{} : Bool},
        {D1.blank(D1.line(r)) == True{} : Bool})))))

# a paragraph of text t is cut at m: a line feed whose next line would not
# fit in cap, or a piece of exactly cap code points with no line feed
def cutc(T: String, cap: Nat, m: Nat, t: String) -> Type:
  Or(Exists(Char, h => Exists(String, r =>
      Pair({String.drop(T, m) == SCon{h, r} : String},
      Pair({D1.nl(h) == True{} : Bool},
        {Nat.is_lt(cap, Nat.add(String.length(t), 1n+String.length(D1.line(r))))
          == True{} : Bool})))),
    Pair({String.length(t) == cap : Nat}, {D1.nonl(t) == True{} : Bool}))

# at m, a line feed, a whitespace line and another line feed
def feedb(T: String, m: Nat) -> Type:
  Exists(Char, h => Exists(String, r =>
    Pair({String.drop(T, m) == SCon{h, r} : String},
    Pair({D1.nl(h) == True{} : Bool},
    Pair({D1.blank(D1.line(r)) == True{} : Bool},
      {D1.nonl(r) == False{} : Bool})))))

# a run's end at m, told apart: only whitespace is left, or a blank line
# follows
def endl(T: String, m: Nat) -> Type:
  Or(Pair({D1.blank(String.drop(T, m)) == True{} : Bool}, rend(T, m)), feedb(T, m))

# where a paragraph ends, with its run's end told apart
def endr(T: String, cap: Nat, m: Nat, t: String) -> Type:
  Or(endl(T, m), cutc(T, cap, m, t))

# p's offsets and text, before its number: some k and l with p from k to
# k + l, its text the l code points at k, k + l inside T, and where it ends
def ok1(T: String, cap: Nat, s: U32, e: U32, t: String) -> Type:
  Exists(Nat, k => Exists(Nat, l =>
    Pair({s == U32.from_nat(k) : U32},
    Pair({e == U32.from_nat(Nat.add(l, k)) : U32},
    Pair({String.take(String.drop(T, k), l) == t : String},
    Pair(Exists(Nat, q =>
      {Nat.add(Nat.add(l, k), q) == String.length(T) : Nat}),
      endr(T, cap, Nat.add(l, k), t)))))))

# what every paragraph of T satisfies: ok1, at most cap long, not blank,
# and holding no blank line
def good(T: String, cap: Nat, p: P.Para) -> Type:
  match p:
    case P.Para{_n, s, e, t}:
      Pair(ok1(T, cap, s, e, t),
        Pair({Nat.is_le(String.length(t), cap) == True{} : Bool},
          Pair({P.Para.blank(t) == False{} : Bool}, {L1.lines_full(t) == True{} : Bool})))

# every paragraph of ps is good
def all(T: String, cap: Nat, ps: List<&2, P.Para>) -> Type:
  match ps:
    case Nil{}:
      Unit
    case Con{h, t}:
      Pair(good(T, cap, h), all(T, cap, t))

# appending is associative
def lapp_assoc(
  -A: Data,
  xs: List<&2, A>,
  -ys: List<&2, A>,
  -zs: List<&2, A>
) -> {List.append(&2, A, List.append(&2, A, xs, ys), zs)
  == List.append(&2, A, xs, List.append(&2, A, ys, zs)) : List<&2, A>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, t}:
      Equal.cong(List<&2, A>, List<&2, A>, x => h <> x,
        List.append(&2, A, List.append(&2, A, t, ys), zs),
        List.append(&2, A, t, List.append(&2, A, ys, zs)), lapp_assoc(A, t, ys, zs))

# --- packing, step by step ---

# the shards a step freezes
def step.out(t: S.Step) -> List<&2, S.Open>:
  match t:
    case S.Step{out, _next}:
      out

# the open shard after a step
def step.next(t: S.Step) -> S.Open:
  match t:
    case S.Step{_out, next}:
      next

# then, by the step's parts
def then_eta(
  t: S.Step,
  -k: S.Open -> List<&2, S.Open>
) -> {S.Shard.then(t, k)
  == List.append(&2, S.Open, step.out(t), k(step.next(t))) : List<&2, S.Open>}:
  match t:
    case S.Step{_out, _next}:
      {==}

# the shards frozen while packing xs after the open shard st
def packed(xs: List<&2, R.Record>, +cap: Nat, +st: S.Open) -> List<&2, S.Open>:
  match xs:
    case Nil{}:
      []
    case Con{+rec, rest}:
      List.append(&2, S.Open, step.out(S.Shard.step(cap, st, rec)),
        packed(rest, cap, step.next(S.Shard.step(cap, st, rec))))

# shards follow when the last of them do
def more_app(
  xs: List<&2, S.Open>,
  -ys: List<&2, S.Open>,
  e: {S.Shard.more(ys) == True{} : Bool}
) -> {S.Shard.more(List.append(&2, S.Open, xs, ys)) == True{} : Bool}:
  match xs:
    case Nil{}:
      e
    case Con{_h, _t}:
      {==}

# packing gives at least one shard
law run_more:
  for xs: List<&2, R.Record>
  for +cap: Nat
  for +st: S.Open
  {S.Shard.more(S.Shard.run(xs, cap, st)) == True{} : Bool}

def run_more(xs, cap, st):
  match xs:
    case Nil{}:
      {==}
    case Con{+rec, +rest}:
      +t = S.Shard.step(cap, st, rec)
      %Equal.sym(List<&2, S.Open>,
        S.Shard.then(t, next => S.Shard.run(rest, cap, next)),
        List.append(&2, S.Open, step.out(t), S.Shard.run(rest, cap, step.next(t))),
        then_eta(t, next => S.Shard.run(rest, cap, next)))
        : {S.Shard.more(_) == True{} : Bool}
      more_app(step.out(t), S.Shard.run(rest, cap, step.next(t)),
        run_more(rest, cap, step.next(t)))

# a word compares EQ with itself
law word_refl:
  for +n: Nat
  for +w: Word(n)
  {Word.cmp(n, w, w) == EQ{} : Cmp}

def word_refl(n, w):
  match n:
    case 0n:
      {==}
    case 1n+(+p):
      match w:
        case WCon{b, +t}:
          match b:
            case False{}:
              %Equal.sym(Cmp, Word.cmp(p, t, t), EQ{}, word_refl(p, t))
                : {Word.cmp.fin(False{}, False{}, _) == EQ{} : Cmp}
              {==}
            case True{}:
              %Equal.sym(Cmp, Word.cmp(p, t, t), EQ{}, word_refl(p, t))
                : {Word.cmp.fin(True{}, True{}, _) == EQ{} : Cmp}
              {==}

# a text compares EQ with itself
law order_refl:
  for +a: String
  {String.order.go(a, a, EQ{}) == EQ{} : Cmp}

def order_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{Chr{x}, +t}:
      match x:
        case U32{+w}:
          %Equal.sym(Cmp, Word.cmp(32n, w, w), EQ{}, word_refl(32n, w))
            : {String.order.go(t, t, _) == EQ{} : Cmp}
          order_refl(t)

# a text equals itself
def eq_refl(+a: String) -> {String.eq(a, a) == True{} : Bool}:
  %Equal.sym(Cmp, String.order.go(a, a, EQ{}), EQ{}, order_refl(a))
    : {Cmp.is_eq(_) == True{} : Bool}
  {==}

# every excerpt of xs has timestamp t
def at_time(-t: String, xs: List<&2, E.Ex>) -> Data:
  match xs:
    case Nil{}:
      Unit
    case Con{x, rest}:
      Sigma<&2, &2, {D1.ex.ts(x) == t : String}, _h => at_time(t, rest)>

# excerpts all of time t are their own excerpts of time t
law only_all:
  for +t: String
  for xs: List<&2, E.Ex>
  for h: at_time(t, xs)
  {D1.only(t, xs) == xs : List<&2, E.Ex>}

def only_all(t, xs, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+a, +rest}:
      match h:
        case (ha, hr):
          %Equal.sym(String, D1.ex.ts(a), t, ha)
            : {List.filter.put(E.Ex, a, D1.only(t, rest), String.eq(_, t))
              == a <> rest : List<&2, E.Ex>}
          %Equal.sym(Bool, String.eq(t, t), True{}, eq_refl(t))
            : {List.filter.put(E.Ex, a, D1.only(t, rest), _) == a <> rest
              : List<&2, E.Ex>}
          Equal.cong(List<&2, E.Ex>, List<&2, E.Ex>, w => a <> w, D1.only(t, rest),
            rest, only_all(t, rest, hr))
