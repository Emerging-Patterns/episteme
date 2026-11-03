# taking and appending code points, and blank texts
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../src/filter.bend as F
import ../../src/excerpt.bend as E
import ../../laws/ParagraphsAreNonBlankRuns.bend as L1
import ../../laws/defs/Specification.bend as D1
import ./BoolFacts.bend as M1
import ./NatArithmetic.bend as M2
import ./PackingSteps.bend as M3

# one more code point taken: the same r still makes up the count
def take_len.up(
  -h: Char,
  -t: String,
  -p: Nat,
  x: Exists(Nat, r => {Nat.add(String.length(String.take(t, p)), r) == p : Nat})
) -> Exists(Nat, r =>
  {Nat.add(String.length(String.take(SCon{h, t}, 1n+p)), r) == 1n+p : Nat}):
  match x:
    case (r, e):
      (r, Equal.cong(Nat, Nat, y => 1n+y,
        Nat.add(String.length(String.take(t, p)), r), p, e))

# taking n code points gives at most n of them
law take_len:
  for s: String
  for +n: Nat
  exs r: Nat
  {Nat.add(String.length(String.take(s, n)), r) == n : Nat}

def take_len(s, n):
  match s n:
    case SNil{} _:
      (n, {==})
    case SCon{_h, _t} 0n:
      (0n, {==})
    case SCon{h, t} 1n+p:
      take_len.up(h, t, p, take_len(t, p))

# a lazy and is an and
def all_if_and(
  b: Bool,
  -x: Bool,
  -y: Bool,
  e: {x == y : Bool}
) -> {List.all.if(_u => x, b) == Bool.and(b, y) : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      e

# the blank test is the specification's own
law blank_same:
  for s: String
  {P.Para.blank(s) == D1.blank(s) : Bool}

def blank_same(s):
  match s:
    case SNil{}:
      {==}
    case SCon{h, t}:
      all_if_and(Char.is_space(h), P.Para.blank(t), D1.blank(t),
        blank_same(t))

# appending is associative
def app_assoc(
  a: String,
  -b: String,
  -c: String
) -> {(a ++ b) ++ c == a ++ (b ++ c) : String}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, t}:
      Equal.cong(String, String, x => SCon{h, x}, (t ++ b) ++ c, t ++ (b ++ c),
        app_assoc(t, b, c))

# the length of a ++ b
def len_app(
  a: String,
  -b: String
) -> {String.length(a ++ b) == Nat.add(String.length(a), String.length(b)) : Nat}:
  match a:
    case SNil{}:
      {==}
    case SCon{_h, t}:
      Equal.cong(Nat, Nat, x => 1n+x, String.length(t ++ b),
        Nat.add(String.length(t), String.length(b)), len_app(t, b))

# taking as many code points as a has from a ++ r gives a
def take_app(a: String, r: String) -> {String.take(a ++ r, String.length(a)) == a : String}:
  match a:
    case SNil{}:
      match r:
        case SNil{}:
          {==}
        case SCon{_h, _t}:
          {==}
    case SCon{+h, t}:
      Equal.cong(String, String, x => SCon{h, x}, String.take(t ++ r, String.length(t)),
        t, take_app(t, r))

# two blank texts make a blank text
def blank_app(
  a: String,
  -b: String,
  +ea: {D1.blank(a) == True{} : Bool},
  eb: {D1.blank(b) == True{} : Bool}
) -> {D1.blank(a ++ b) == True{} : Bool}:
  match a:
    case SNil{}:
      eb
    case SCon{+h, t}:
      %Equal.sym(Bool, Char.is_space(h), True{},
          M1.and_l(Char.is_space(h), D1.blank(t), ea))
        : {Bool.and(_, D1.blank(t ++ b)) == True{} : Bool}
      blank_app(t, b, M1.and_r(Char.is_space(h), D1.blank(t), ea), eb)

# two gaps in a row make one
def gap_cat(
  -T: String,
  +E: Nat,
  -M: Nat,
  -S: Nat,
  g1: M1.gap(T, E, M),
  g2: M1.gap(T, M, S)
) -> M1.gap(T, E, S):
  match g1:
    case (+G1, (e1, (l1, b1))):
      match g2:
        case (+G2, (e2, (l2, b2))):
          (G1 ++ G2,
            (Equal.trans(String, String.drop(T, E), G1 ++ String.drop(T, M),
              (G1 ++ G2) ++ String.drop(T, S), e1,
              Equal.trans(String, G1 ++ String.drop(T, M),
                G1 ++ (G2 ++ String.drop(T, S)), (G1 ++ G2) ++ String.drop(T, S),
                Equal.cong(String, String, z => G1 ++ z, String.drop(T, M),
                  G2 ++ String.drop(T, S), e2),
                Equal.sym(String, (G1 ++ G2) ++ String.drop(T, S),
                  G1 ++ (G2 ++ String.drop(T, S)),
                  app_assoc(G1, G2, String.drop(T, S))))),
            (Equal.trans(Nat, Nat.add(E, String.length(G1 ++ G2)),
              Nat.add(E, Nat.add(String.length(G1), String.length(G2))), S,
              Equal.cong(Nat, Nat, z => Nat.add(E, z), String.length(G1 ++ G2),
                Nat.add(String.length(G1), String.length(G2)), len_app(G1, G2)),
              Equal.trans(Nat, Nat.add(E, Nat.add(String.length(G1), String.length(G2))),
                Nat.add(Nat.add(E, String.length(G1)), String.length(G2)), S,
                Equal.sym(Nat, Nat.add(Nat.add(E, String.length(G1)), String.length(G2)),
                  Nat.add(E, Nat.add(String.length(G1), String.length(G2))),
                  M2.add_assoc(E, String.length(G1), String.length(G2))),
                (%Equal.sym(Nat, Nat.add(E, String.length(G1)), M, l1)
                  : {Nat.add(_, String.length(G2)) == S : Nat}; l2))),
            blank_app(G1, G2, b1, b2))))

# a blank text X from ks, len code points long, is a gap
def gap_span(
  -T: String,
  +ks: Nat,
  +X: String,
  +len: Nat,
  ex: {String.drop(T, ks) == X ++ String.drop(T, Nat.add(len, ks)) : String},
  elx: {String.length(X) == len : Nat},
  eb: {D1.blank(X) == True{} : Bool}
) -> M1.gap(T, ks, Nat.add(len, ks)):
  (X, (ex,
    (Equal.trans(Nat, Nat.add(ks, String.length(X)), Nat.add(ks, len),
      Nat.add(len, ks),
      Equal.cong(Nat, Nat, z => Nat.add(ks, z), String.length(X), len, elx),
      M2.add_comm(ks, len)), eb)))

# a gap before a tile extends it
def tile_pre(
  ps: List<&2, P.Para>,
  -T: String,
  +E: Nat,
  -M: Nat,
  -F: Nat,
  g: M1.gap(T, E, M),
  t: M2.tile(T, M, ps, F)
) -> M2.tile(T, E, ps, F):
  match ps:
    case Nil{}:
      gap_cat(T, E, M, F, g, t)
    case Con{p, _rest}:
      match p:
        case P.Para{_n, _s, _e, _x}:
          match t:
            case (+ks, (ke, (es, (ee, (g2, rest))))):
              (ks, (ke, (es, (ee, (gap_cat(T, E, M, ks, g, g2), rest)))))

# --- emitting a paragraph ---

# taking len code points of suf gives len, less some r
def taken(suf: String, len: Nat) -> Type:
  Exists(Nat, r =>
    {Nat.add(String.length(String.take(suf, len)), r) == len : Nat})

# the first len code points of suf are at most cap long, from the d with
# len + d == cap and the r with that text's length + r == len
def le_take.go(
  +suf: String,
  +len: Nat,
  -cap: Nat,
  +d: Nat,
  ed: {Nat.add(len, d) == cap : Nat},
  x: taken(suf, len)
) -> {Nat.is_le(String.length(String.take(suf, len)), cap) == True{} : Bool}:
  match x:
    case (+r, er):
      %Equal.trans(Nat,
          Nat.add(String.length(String.take(suf, len)), Nat.add(r, d)),
          Nat.add(Nat.add(String.length(String.take(suf, len)), r), d), cap,
          Equal.sym(Nat,
            Nat.add(Nat.add(String.length(String.take(suf, len)), r), d),
            Nat.add(String.length(String.take(suf, len)), Nat.add(r, d)),
            M2.add_assoc(String.length(String.take(suf, len)), r, d)),
          (%Equal.sym(Nat, Nat.add(String.length(String.take(suf, len)), r),
              len, er) : {Nat.add(_, d) == cap : Nat}; ed))
        : {Nat.is_le(String.length(String.take(suf, len)), _) == True{} : Bool}
      M2.le_add(String.length(String.take(suf, len)), Nat.add(r, d))

# an emitted span is kept when not blank, and is good; kept or not, the
# tile from E runs on through it
def put.if(
  -T: String,
  -cap: Nat,
  +E: Nat,
  bl: Bool,
  +suf: String,
  -start: U32,
  -end: U32,
  +len: Nat,
  ps: List<&2, P.Para>,
  -M: Nat,
  +ks: Nat,
  +X: String,
  +es: {start == U32.from_nat(ks) : U32},
  +edp: {String.drop(T, ks) == suf : String},
  +ee: {end == U32.from_nat(Nat.add(len, ks)) : U32},
  +q: Nat,
  +eqq: {Nat.add(Nat.add(len, ks), q) == String.length(T) : Nat},
  +d: Nat,
  edd: {Nat.add(len, d) == cap : Nat},
  ex: {suf == X ++ String.drop(T, Nat.add(len, ks)) : String},
  elx: {String.length(X) == len : Nat},
  +etx: {String.take(suf, len) == X : String},
  +eb: {P.Para.blank(String.take(suf, len)) == bl : Bool},
  ec: M3.endr(T, cap, Nat.add(len, ks), X),
  nob: {Bool.or(D1.blank(X), L1.lines_full(X)) == True{} : Bool},
  gE: M1.gap(T, E, ks),
  a: M3.all(T, cap, ps),
  tp: M2.tile(T, Nat.add(len, ks), ps, M)
) -> Pair(M3.all(T, cap, P.Para.emit.if(bl,
    P.Para{0, start, end, String.take(suf, len)}, ps)),
  M2.tile(T, E, P.Para.emit.if(bl,
    P.Para{0, start, end, String.take(suf, len)}, ps), M)):
  match bl:
    case True{}:
      (a, tile_pre(ps, T, E, Nat.add(len, ks), M,
        gap_cat(T, E, ks, Nat.add(len, ks), gE,
          gap_span(T, ks, X, len,
            Equal.trans(String, String.drop(T, ks), suf,
              X ++ String.drop(T, Nat.add(len, ks)), edp, ex), elx,
            Equal.trans(Bool, D1.blank(X), P.Para.blank(X), True{},
              Equal.sym(Bool, P.Para.blank(X), D1.blank(X), blank_same(X)),
              (%etx : {P.Para.blank(_) == True{} : Bool}; eb)))), tp))
    case False{}:
      ((((ks, (len, (es, (ee,
        (Equal.cong(String, String, z => String.take(z, len),
          String.drop(T, ks), suf, edp),
        ((q, eqq),
          (%Equal.sym(String, String.take(suf, len), X, etx)
            : M3.endr(T, cap, Nat.add(len, ks), _); ec))))))),
        (le_take.go(suf, len, cap, d, edd, take_len(suf, len)),
          (eb, (%Equal.sym(String, String.take(suf, len), X, etx)
            : {L1.lines_full(_) == True{} : Bool};
            Equal.trans(Bool, L1.lines_full(X), Bool.or(D1.blank(X), L1.lines_full(X)),
              True{},
              Equal.cong(Bool, Bool, z => Bool.or(z, L1.lines_full(X)), False{},
                D1.blank(X),
                Equal.sym(Bool, D1.blank(X), False{},
                  Equal.trans(Bool, D1.blank(X), P.Para.blank(X), False{},
                    Equal.sym(Bool, P.Para.blank(X), D1.blank(X), blank_same(X)),
                    (%etx : {P.Para.blank(_) == False{} : Bool}; eb)))),
              nob))))), a),
        (ks, (Nat.add(len, ks), (es, (ee, (gE,
          ((len, M2.add_comm(ks, len)), ((q, eqq), tp))))))))

# emitting a span: put.if, with the text it takes
def put(
  T: String,
  -cap: Nat,
  +E: Nat,
  +suf: String,
  -start: U32,
  -end: U32,
  +len: Nat,
  ps: List<&2, P.Para>,
  -M: Nat,
  +ks: Nat,
  +X: String,
  es: {start == U32.from_nat(ks) : U32},
  edp: {String.drop(T, ks) == suf : String},
  ee: {end == U32.from_nat(Nat.add(len, ks)) : U32},
  +q: Nat,
  +eqq: {Nat.add(Nat.add(len, ks), q) == String.length(T) : Nat},
  +d: Nat,
  edd: {Nat.add(len, d) == cap : Nat},
  +ex: {suf == X ++ String.drop(T, Nat.add(len, ks)) : String},
  +elx: {String.length(X) == len : Nat},
  ec: M3.endr(T, cap, Nat.add(len, ks), X),
  nob: {Bool.or(D1.blank(X), L1.lines_full(X)) == True{} : Bool},
  gE: M1.gap(T, E, ks),
  a: M3.all(T, cap, ps),
  tp: M2.tile(T, Nat.add(len, ks), ps, M)
) -> Pair(M3.all(T, cap, P.Para.emit(suf, start, end, len, ps)),
  M2.tile(T, E, P.Para.emit(suf, start, end, len, ps), M)):
  put.if(T, cap, E, P.Para.blank(String.take(suf, len)), suf, start, end, len,
    ps, M, ks, X, es, edp, ee, q, eqq, d, edd, ex, elx,
    Equal.trans(String, String.take(suf, len),
      String.take(X ++ String.drop(T, Nat.add(len, ks)), len), X,
      Equal.cong(String, String, z => String.take(z, len), suf,
        X ++ String.drop(T, Nat.add(len, ks)), ex),
      (%elx : {String.take(X ++ String.drop(T, Nat.add(len, ks)), _) == X : String};
        take_app(X, String.drop(T, Nat.add(len, ks))))),
    {==}, ec, nob, gE, a, tp)

# --- sources: ascending ---

# a true and of two trues
def and_tt(
  a: Bool,
  -b: Bool,
  ea: {a == True{} : Bool},
  eb: {b == True{} : Bool}
) -> {Bool.and(a, b) == True{} : Bool}:
  %Equal.sym(Bool, a, True{}, ea) : {Bool.and(_, b) == True{} : Bool}
  eb

# the code's timestamp of an excerpt is the specification's
def ts_eq(x: E.Ex) -> {E.Excerpt.ts(E.Excerpt.rec(x)) == D1.ex.ts(x) : String}:
  match x:
    case E.Ex{rec, _ps}:
      match rec:
        case R.Record{_id, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
          {==}
