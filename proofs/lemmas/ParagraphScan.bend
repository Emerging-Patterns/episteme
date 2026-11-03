# the scan Para.split runs, and its invariant
import Base
import ../../src/para.bend as P
import ../../src/filter.bend as F
import ../../src/excerpt.bend as E
import ../../laws/ParagraphsAreNonBlankRuns.bend as L1
import ../../laws/defs/Specification.bend as D1
import ./BoolFacts.bend as M1
import ./NatArithmetic.bend as M2
import ./PackingSteps.bend as M3
import ./TakeAndAppend.bend as M4
import ./TextOrder.bend as M5

# taking b back off a + b leaves a
law sub_add:
  for +a: Nat
  for +b: Nat
  {Nat.sub(Nat.add(a, b), b) == a : Nat}

def sub_add(a, b):
  match b:
    case 0n:
      %Equal.sym(Nat, Nat.add(a, 0n), a, M2.add_zero_r(a))
        : {Nat.sub(_, 0n) == a : Nat}
      M2.sub_zero(a)
    case 1n+q:
      %Equal.sym(Nat, Nat.add(a, 1n+q), 1n+Nat.add(a, q), M2.add_succ_r(a, q))
        : {Nat.sub(_, 1n+q) == a : Nat}
      sub_add(a, q)

# --- more Nat facts ---

# x is less than x + 1 + b
law lt_add:
  for +x: Nat
  for +b: Nat
  {Nat.is_lt(x, Nat.add(x, 1n+b)) == True{} : Bool}

def lt_add(x, b):
  match x:
    case 0n:
      {==}
    case 1n+p:
      lt_add(p, b)

# a true not is of a false
def not_true(a: Bool, e: {Bool.not(a) == True{} : Bool}) -> {a == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({True{} == False{} : Bool}, M1.clash(e))

# --- more String facts ---

# appending nothing changes nothing
def app_nil(a: String) -> {a ++ "" == a : String}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, t}:
      Equal.cong(String, String, x => SCon{h, x}, t ++ "", t, app_nil(t))

# one whitespace code point is blank
def blank_one(-c: Char, e: {Char.is_space(c) == True{} : Bool}) -> {D1.blank(SCon{c, SNil{}}) == True{} : Bool}:
  %Equal.sym(Bool, Char.is_space(c), True{}, e)
    : {Bool.and(_, True{}) == True{} : Bool}
  {==}

# two texts with no line feed make one
def nonl_app(
  a: String,
  -b: String,
  +ea: {D1.nonl(a) == True{} : Bool},
  eb: {D1.nonl(b) == True{} : Bool}
) -> {D1.nonl(a ++ b) == True{} : Bool}:
  match a:
    case SNil{}:
      eb
    case SCon{+h, t}:
      %Equal.sym(Bool, Bool.not(D1.nl(h)), True{},
          M1.and_l(Bool.not(D1.nl(h)), D1.nonl(t), ea))
        : {Bool.and(_, D1.nonl(t ++ b)) == True{} : Bool}
      nonl_app(t, b, M1.and_r(Bool.not(D1.nl(h)), D1.nonl(t), ea), eb)

# one code point that is no line feed has none
def nonl_one(-c: Char, e: {D1.nl(c) == False{} : Bool}) -> {D1.nonl(SCon{c, SNil{}}) == True{} : Bool}:
  %Equal.sym(Bool, D1.nl(c), False{}, e)
    : {Bool.and(Bool.not(_), True{}) == True{} : Bool}
  {==}

# the first line of a ++ a line feed ++ t is a, when a has no line feed
def line_stop(
  a: String,
  -h: Char,
  -t: String,
  +ea: {D1.nonl(a) == True{} : Bool},
  eh: {D1.nl(h) == True{} : Bool}
) -> {D1.line(a ++ SCon{h, t}) == a : String}:
  match a:
    case SNil{}:
      %Equal.sym(Bool, D1.nl(h), True{}, eh)
        : {D1.line.if(_, h, _u => D1.line(t)) == SNil{} : String}
      {==}
    case SCon{+x, y}:
      %Equal.sym(Bool, D1.nl(x), False{},
          not_true(D1.nl(x), M1.and_l(Bool.not(D1.nl(x)), D1.nonl(y), ea)))
        : {D1.line.if(_, x, _u => D1.line(y ++ SCon{h, t})) == SCon{x, y} : String}
      Equal.cong(String, String, z => SCon{x, z}, D1.line(y ++ SCon{h, t}), y,
        line_stop(y, h, t, M1.and_r(Bool.not(D1.nl(x)), D1.nonl(y), ea), eh))

# the first line of a with no line feed is a
def line_all(a: String, +ea: {D1.nonl(a) == True{} : Bool}) -> {D1.line(a) == a : String}:
  match a:
    case SNil{}:
      {==}
    case SCon{+x, y}:
      %Equal.sym(Bool, D1.nl(x), False{},
          not_true(D1.nl(x), M1.and_l(Bool.not(D1.nl(x)), D1.nonl(y), ea)))
        : {D1.line.if(_, x, _u => D1.line(y)) == SCon{x, y} : String}
      Equal.cong(String, String, z => SCon{x, z}, D1.line(y), y,
        line_all(y, M1.and_r(Bool.not(D1.nl(x)), D1.nonl(y), ea)))

# the first line of a ++ c ++ t, c no line feed, runs on into t
def line_go(
  a: String,
  -c: Char,
  -t: String,
  +ea: {D1.nonl(a) == True{} : Bool},
  ec: {D1.nl(c) == False{} : Bool}
) -> {D1.line(a ++ SCon{c, t}) == a ++ SCon{c, D1.line(t)} : String}:
  match a:
    case SNil{}:
      %Equal.sym(Bool, D1.nl(c), False{}, ec)
        : {D1.line.if(_, c, _u => D1.line(t)) == SCon{c, D1.line(t)} : String}
      {==}
    case SCon{+x, y}:
      %Equal.sym(Bool, D1.nl(x), False{},
          not_true(D1.nl(x), M1.and_l(Bool.not(D1.nl(x)), D1.nonl(y), ea)))
        : {D1.line.if(_, x, _u => D1.line(y ++ SCon{c, t}))
          == SCon{x, y ++ SCon{c, D1.line(t)}} : String}
      Equal.cong(String, String, z => SCon{x, z}, D1.line(y ++ SCon{c, t}),
        y ++ SCon{c, D1.line(t)},
        line_go(y, c, t, M1.and_r(Bool.not(D1.nl(x)), D1.nonl(y), ea), ec))

# the line feed is whitespace
def nl_space(c: Char, e: {D1.nl(c) == True{} : Bool}) -> {Char.is_space(c) == True{} : Bool}:
  match c:
    case Chr{+x}:
      %Equal.sym(U32, x, 10, M5.u32_eq(x, 10, M5.cmp_eq(U32.cmp(x, 10), e)))
        : {Char.is_space(Chr{_}) == True{} : Bool}
      {==}

# an empty gap
def gap_nil(-T: String, +m: Nat) -> M1.gap(T, m, m):
  (SNil{}, ({==}, (M2.add_zero_r(m), {==})))

# one whitespace code point at m is a gap
def gap_one(
  +T: String,
  +m: Nat,
  +h: Char,
  -x: String,
  +e: {String.drop(T, m) == SCon{h, x} : String},
  es: {Char.is_space(h) == True{} : Bool}
) -> M1.gap(T, m, 1n+m):
  (SCon{h, SNil{}},
    (Equal.trans(String, String.drop(T, m), SCon{h, x},
      SCon{h, String.drop(T, 1n+m)}, e,
      Equal.cong(String, String, z => SCon{h, z}, x, String.drop(T, 1n+m),
        Equal.sym(String, String.drop(T, 1n+m), x, M2.drop_step(T, m, h, x, e)))),
    (Equal.trans(Nat, Nat.add(m, 1n), 1n+Nat.add(m, 0n), 1n+m, M2.add_succ_r(m, 0n),
      Equal.cong(Nat, Nat, z => 1n+z, Nat.add(m, 0n), m, M2.add_zero_r(m))),
    blank_one(h, es))))

# --- no blank line inside ---

# or with True on the right is True
def or_true(b: Bool) -> {Bool.or(b, True{}) == True{} : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

# a ++ a line feed ++ t has a line feed
def nonl_feed(
  a: String,
  -c: Char,
  -t: String,
  +enc: {D1.nl(c) == True{} : Bool}
) -> {D1.nonl(a ++ SCon{c, t}) == False{} : Bool}:
  match a:
    case SNil{}:
      %Equal.sym(Bool, D1.nl(c), True{}, enc)
        : {Bool.and(Bool.not(_), D1.nonl(t)) == False{} : Bool}
      {==}
    case SCon{+x, y}:
      %Equal.sym(Bool, D1.nonl(y ++ SCon{c, t}), False{}, nonl_feed(y, c, t, enc))
        : {Bool.and(Bool.not(D1.nl(x)), _) == False{} : Bool}
      M2.and_false(Bool.not(D1.nl(x)))

# and is associative
def and_assoc(
  a: Bool,
  -b: Bool,
  -c: Bool
) -> {Bool.and(a, Bool.and(b, c)) == Bool.and(Bool.and(a, b), c) : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

# a not that is True is of False
def not_t(b: Bool, e: {Bool.not(b) == True{} : Bool}) -> {b == False{} : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({True{} == False{} : Bool}, M1.clash(e))

# text with no line feed is its own first line
def line_nonl(a: String, +ea: {D1.nonl(a) == True{} : Bool}) -> {D1.line(a) == a : String}:
  match a:
    case SNil{}:
      {==}
    case SCon{+x, y}:
      %Equal.sym(Bool, D1.nl(x), False{},
          not_t(D1.nl(x), M1.and_l(Bool.not(D1.nl(x)), D1.nonl(y), ea)))
        : {D1.line.if(_, x, _u => D1.line(y)) == SCon{x, y} : String}
      Equal.cong(String, String, v => SCon{x, v}, D1.line(y), y,
        line_nonl(y, M1.and_r(Bool.not(D1.nl(x)), D1.nonl(y), ea)))

# the first line of y and then a line feed is the first line of y
def line_feed(
  y: String,
  -h: Char,
  -z: String,
  +enh: {D1.nl(h) == True{} : Bool}
) -> {D1.line(y ++ SCon{h, z}) == D1.line(y) : String}:
  match y:
    case SNil{}:
      %Equal.sym(Bool, D1.nl(h), True{}, enh)
        : {D1.line.if(_, h, _u => D1.line(z)) == SNil{} : String}
      {==}
    case SCon{+x, w}:
      Equal.cong(String, String, v => D1.line.if(D1.nl(x), x, _u => v),
        D1.line(w ++ SCon{h, z}), D1.line(w),
        line_feed(w, h, z, enh))

# text with no line feed has every line feed followed by a full line
def fed_nonl(a: String, +ea: {D1.nonl(a) == True{} : Bool}) -> {L1.fedok(a) == True{} : Bool}:
  match a:
    case SNil{}:
      {==}
    case SCon{+x, y}:
      %Equal.sym(Bool, Bool.not(D1.nl(x)), True{},
          M1.and_l(Bool.not(D1.nl(x)), D1.nonl(y), ea))
        : {Bool.and(Bool.or(_, Bool.not(D1.blank(D1.line(y)))), L1.fedok(y))
          == True{} : Bool}
      fed_nonl(y, M1.and_r(Bool.not(D1.nl(x)), D1.nonl(y), ea))

# fedok of y, a line feed and z splits at the line feed
def fed_app(
  y: String,
  +h: Char,
  +z: String,
  +enh: {D1.nl(h) == True{} : Bool}
) -> {L1.fedok(y ++ SCon{h, z}) == Bool.and(L1.fedok(y), L1.fedok(SCon{h, z})) : Bool}:
  match y:
    case SNil{}:
      {==}
    case SCon{+c, +t}:
      %Equal.sym(String, D1.line(t ++ SCon{h, z}), D1.line(t), line_feed(t, h, z, enh))
        : {Bool.and(Bool.or(Bool.not(D1.nl(c)), Bool.not(D1.blank(_))),
          L1.fedok(t ++ SCon{h, z}))
          == Bool.and(Bool.and(Bool.or(Bool.not(D1.nl(c)),
            Bool.not(D1.blank(D1.line(t)))), L1.fedok(t)), L1.fedok(SCon{h, z})) : Bool}
      %Equal.sym(Bool, L1.fedok(t ++ SCon{h, z}),
          Bool.and(L1.fedok(t), L1.fedok(SCon{h, z})), fed_app(t, h, z, enh))
        : {Bool.and(Bool.or(Bool.not(D1.nl(c)), Bool.not(D1.blank(D1.line(t)))), _)
          == Bool.and(Bool.and(Bool.or(Bool.not(D1.nl(c)),
            Bool.not(D1.blank(D1.line(t)))), L1.fedok(t)), L1.fedok(SCon{h, z})) : Bool}
      and_assoc(Bool.or(Bool.not(D1.nl(c)), Bool.not(D1.blank(D1.line(t)))),
        L1.fedok(t), L1.fedok(SCon{h, z}))

# B, a line feed h and a non-blank line A with no line feed: every line
# feed is followed by a full line when it is so in B
def fed_join(
  +B: String,
  +h: Char,
  +A: String,
  +enh: {D1.nl(h) == True{} : Bool},
  +enl: {D1.nonl(A) == True{} : Bool},
  eim: {D1.blank(A) == False{} : Bool},
  e2: {L1.fedok(B) == True{} : Bool}
) -> {L1.fedok(B ++ SCon{h, A}) == True{} : Bool}:
  %Equal.sym(Bool, L1.fedok(B ++ SCon{h, A}),
      Bool.and(L1.fedok(B), L1.fedok(SCon{h, A})), fed_app(B, h, A, enh))
    : {_ == True{} : Bool}
  %Equal.sym(Bool, L1.fedok(B), True{}, e2)
    : {Bool.and(_, L1.fedok(SCon{h, A})) == True{} : Bool}
  %Equal.sym(Bool, D1.nl(h), True{}, enh)
    : {Bool.and(Bool.or(Bool.not(_), Bool.not(D1.blank(D1.line(A)))), L1.fedok(A))
      == True{} : Bool}
  %Equal.sym(String, D1.line(A), A, line_nonl(A, enl))
    : {Bool.and(Bool.or(Bool.not(True{}), Bool.not(D1.blank(_))), L1.fedok(A))
      == True{} : Bool}
  %Equal.sym(Bool, D1.blank(A), False{}, eim)
    : {Bool.and(Bool.or(Bool.not(True{}), Bool.not(_)), L1.fedok(A)) == True{} : Bool}
  %Equal.sym(Bool, L1.fedok(A), True{}, fed_nonl(A, enl))
    : {Bool.and(Bool.or(Bool.not(True{}), Bool.not(False{})), _) == True{} : Bool}
  {==}

# a block's text is blank or has every line full
def blk_full(
  +B: String,
  e1: {D1.blank(D1.line(B)) == False{} : Bool},
  e2: {L1.fedok(B) == True{} : Bool}
) -> {Bool.or(D1.blank(B), L1.lines_full(B)) == True{} : Bool}:
  %Equal.sym(Bool, D1.blank(D1.line(B)), False{}, e1)
    : {Bool.or(D1.blank(B), Bool.and(Bool.not(_), L1.fedok(B))) == True{} : Bool}
  %Equal.sym(Bool, L1.fedok(B), True{}, e2)
    : {Bool.or(D1.blank(B), Bool.and(Bool.not(False{}), _)) == True{} : Bool}
  or_true(D1.blank(B))

# b, or not b
def or_not(b: Bool) -> {Bool.or(b, Bool.and(Bool.not(b), True{})) == True{} : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

# a piece with no line feed is blank or has its one line full
def nonl_full(
  +A: String,
  +enl: {D1.nonl(A) == True{} : Bool}
) -> {Bool.or(D1.blank(A), L1.lines_full(A)) == True{} : Bool}:
  %Equal.sym(String, D1.line(A), A, line_nonl(A, enl))
    : {Bool.or(D1.blank(A), Bool.and(Bool.not(D1.blank(_)), L1.fedok(A))) == True{} : Bool}
  %Equal.sym(Bool, L1.fedok(A), True{}, fed_nonl(A, enl))
    : {Bool.or(D1.blank(A), Bool.and(Bool.not(D1.blank(A)), _)) == True{} : Bool}
  or_not(D1.blank(A))

# a paragraph of a good list is good
def in_good(
  -T: String,
  -cap: Nat,
  -p: P.Para,
  ps: List<&2, P.Para>,
  h: D1.In(p, ps),
  a: M3.all(T, cap, ps)
) -> M3.good(T, cap, p):
  match ps:
    case Nil{}:
      match h:
    case Con{x, t}:
      match h:
        case Inl{e}:
          match a:
            case (g, _r):
              %Equal.sym(P.Para, p, x, e) : M3.good(T, cap, _)
              g
        case Inr{i}:
          match a:
            case (_g, r):
              in_good(T, cap, p, t, i, r)

# two good lists make a good list
def all_append(
  -T: String,
  -cap: Nat,
  xs: List<&2, P.Para>,
  -ys: List<&2, P.Para>,
  a: M3.all(T, cap, xs),
  b: M3.all(T, cap, ys)
) -> M3.all(T, cap, List.append(&2, P.Para, xs, ys)):
  match xs:
    case Nil{}:
      b
    case Con{_x, t}:
      match a:
        case (g, r):
          (g, all_append(T, cap, t, ys, r, b))

# numbering keeps a good list good
def all_number(
  -T: String,
  -cap: Nat,
  xs: List<&2, P.Para>,
  +i: U32,
  a: M3.all(T, cap, xs)
) -> M3.all(T, cap, P.Para.number(xs, i)):
  match xs:
    case Nil{}:
      Unit{}
    case Con{p, rest}:
      match p:
        case P.Para{_n, _s, _e, _t}:
          match a:
            case (g, r):
              (g, all_number(T, cap, rest, U32.inc(i), r))

# two tiles in a row make one
def tile_app(
  xs: List<&2, P.Para>,
  -T: String,
  +E: Nat,
  -M: Nat,
  ys: List<&2, P.Para>,
  -F: Nat,
  t1: M2.tile(T, E, xs, M),
  t2: M2.tile(T, M, ys, F)
) -> M2.tile(T, E, List.append(&2, P.Para, xs, ys), F):
  match xs:
    case Nil{}:
      M4.tile_pre(ys, T, E, M, F, t1, t2)
    case Con{p, rest}:
      match p:
        case P.Para{_n, _s, _e, _x}:
          match t1:
            case (ks, (+ke, (es, (ee, (g, (d, (q, t3))))))):
              (ks, (ke, (es, (ee, (g, (d, (q,
                tile_app(rest, T, ke, M, ys, F, t3, t2))))))))

# numbering keeps a tile
def tile_number(
  xs: List<&2, P.Para>,
  -T: String,
  -E: Nat,
  -F: Nat,
  +i: U32,
  t: M2.tile(T, E, xs, F)
) -> M2.tile(T, E, P.Para.number(xs, i), F):
  match xs:
    case Nil{}:
      t
    case Con{p, rest}:
      match p:
        case P.Para{_n, _s, _e, _x}:
          match t:
            case (ks, (+ke, (es, (ee, (g, (d, (q, t3))))))):
              (ks, (ke, (es, (ee, (g, (d, (q,
                tile_number(rest, T, ke, F, U32.inc(i), t3))))))))

# --- arithmetic for the scan ---

# l + (p + r) == p + (l + r)
law add_swap:
  for +l: Nat
  for +p: Nat
  for +r: Nat
  {Nat.add(l, Nat.add(p, r)) == Nat.add(p, Nat.add(l, r)) : Nat}

def add_swap(l, p, r):
  Equal.trans(Nat, Nat.add(l, Nat.add(p, r)), Nat.add(Nat.add(l, p), r),
    Nat.add(p, Nat.add(l, r)),
    Equal.sym(Nat, Nat.add(Nat.add(l, p), r), Nat.add(l, Nat.add(p, r)),
      M2.add_assoc(l, p, r)),
    Equal.trans(Nat, Nat.add(Nat.add(l, p), r), Nat.add(Nat.add(p, l), r),
      Nat.add(p, Nat.add(l, r)),
      Equal.cong(Nat, Nat, x => Nat.add(x, r), Nat.add(l, p), Nat.add(p, l),
        M2.add_comm(l, p)),
      M2.add_assoc(p, l, r)))

# the room left once a line of l joins a block of p: (l + (1 + p)) + r
# == p + (l + (1 + r))
law add_join:
  for +l: Nat
  for +p: Nat
  for +r: Nat
  {Nat.add(Nat.add(l, 1n+p), r) == Nat.add(p, Nat.add(l, 1n+r)) : Nat}

def add_join(l, p, r):
  Equal.trans(Nat, Nat.add(Nat.add(l, 1n+p), r), 1n+Nat.add(l, Nat.add(p, r)),
    Nat.add(p, Nat.add(l, 1n+r)),
    Equal.trans(Nat, Nat.add(Nat.add(l, 1n+p), r), Nat.add(l, 1n+Nat.add(p, r)),
      1n+Nat.add(l, Nat.add(p, r)),
      M2.add_assoc(l, 1n+p, r), M2.add_succ_r(l, Nat.add(p, r))),
    Equal.trans(Nat, 1n+Nat.add(l, Nat.add(p, r)), 1n+Nat.add(p, Nat.add(l, r)),
      Nat.add(p, Nat.add(l, 1n+r)),
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(l, Nat.add(p, r)),
        Nat.add(p, Nat.add(l, r)), add_swap(l, p, r)),
      Equal.sym(Nat, Nat.add(p, Nat.add(l, 1n+r)), 1n+Nat.add(p, Nat.add(l, r)),
        Equal.trans(Nat, Nat.add(p, Nat.add(l, 1n+r)), Nat.add(p, 1n+Nat.add(l, r)),
          1n+Nat.add(p, Nat.add(l, r)),
          Equal.cong(Nat, Nat, x => Nat.add(p, x), Nat.add(l, 1n+r),
            1n+Nat.add(l, r), M2.add_succ_r(l, r)),
          M2.add_succ_r(p, Nat.add(l, r))))))

# p + (1 + l) == l + (1 + p)
def add_flip(+p: Nat, +l: Nat) -> {Nat.add(p, 1n+l) == Nat.add(l, 1n+p) : Nat}:
  Equal.trans(Nat, Nat.add(p, 1n+l), 1n+Nat.add(p, l), Nat.add(l, 1n+p),
    M2.add_succ_r(p, l),
    Equal.trans(Nat, 1n+Nat.add(p, l), 1n+Nat.add(l, p), Nat.add(l, 1n+p),
      Equal.cong(Nat, Nat, x => 1n+x, Nat.add(p, l), Nat.add(l, p),
        M2.add_comm(p, l)),
      Equal.sym(Nat, Nat.add(l, 1n+p), 1n+Nat.add(l, p), M2.add_succ_r(l, p))))

# a line of l, with no room left beside a block of p, does not fit
def lt_room0(+p: Nat, +l: Nat) -> {Nat.is_lt(Nat.add(p, Nat.add(l, 0n)), Nat.add(p, 1n+l)) == True{} : Bool}:
  %Equal.sym(Nat, Nat.add(l, 0n), l, M2.add_zero_r(l))
    : {Nat.is_lt(Nat.add(p, _), Nat.add(p, 1n+l)) == True{} : Bool}
  %Equal.trans(Nat, Nat.add(Nat.add(p, l), 1n), 1n+Nat.add(Nat.add(p, l), 0n),
      Nat.add(p, 1n+l), M2.add_succ_r(Nat.add(p, l), 0n),
      Equal.trans(Nat, 1n+Nat.add(Nat.add(p, l), 0n), 1n+Nat.add(p, l),
        Nat.add(p, 1n+l),
        Equal.cong(Nat, Nat, x => 1n+x, Nat.add(Nat.add(p, l), 0n), Nat.add(p, l),
          M2.add_zero_r(Nat.add(p, l))),
        Equal.sym(Nat, Nat.add(p, 1n+l), 1n+Nat.add(p, l), M2.add_succ_r(p, l))))
    : {Nat.is_lt(Nat.add(p, l), _) == True{} : Bool}
  lt_add(Nat.add(p, l), 0n)

# x is less than x grown by r + (1 + m) inside
def lt_gen(
  +p: Nat,
  +l: Nat,
  +r: Nat,
  +m: Nat
) -> {Nat.is_lt(Nat.add(p, Nat.add(l, r)), Nat.add(p, Nat.add(l, Nat.add(r, 1n+m))))
  == True{} : Bool}:
  %Equal.trans(Nat, Nat.add(Nat.add(p, Nat.add(l, r)), 1n+m),
      Nat.add(p, Nat.add(Nat.add(l, r), 1n+m)),
      Nat.add(p, Nat.add(l, Nat.add(r, 1n+m))),
      M2.add_assoc(p, Nat.add(l, r), 1n+m),
      Equal.cong(Nat, Nat, x => Nat.add(p, x), Nat.add(Nat.add(l, r), 1n+m),
        Nat.add(l, Nat.add(r, 1n+m)), M2.add_assoc(l, r, 1n+m)))
    : {Nat.is_lt(Nat.add(p, Nat.add(l, r)), _) == True{} : Bool}
  lt_add(Nat.add(p, Nat.add(l, r)), m)

# a block of p beside a line of l + 1 and room r never fits in a cap of l
def no_grow(+p: Nat, +x: Nat, +r: Nat, e: {Nat.add(p, 1n+Nat.add(x, r)) == x : Nat}) -> Empty:
  M2.no_loop(x, Nat.add(p, r),
    Equal.trans(Nat, Nat.add(x, 1n+Nat.add(p, r)), Nat.add(p, 1n+Nat.add(x, r)), x,
      Equal.trans(Nat, Nat.add(x, 1n+Nat.add(p, r)), 1n+Nat.add(x, Nat.add(p, r)),
        Nat.add(p, 1n+Nat.add(x, r)), M2.add_succ_r(x, Nat.add(p, r)),
        Equal.trans(Nat, 1n+Nat.add(x, Nat.add(p, r)), 1n+Nat.add(p, Nat.add(x, r)),
          Nat.add(p, 1n+Nat.add(x, r)),
          Equal.cong(Nat, Nat, z => 1n+z, Nat.add(x, Nat.add(p, r)),
            Nat.add(p, Nat.add(x, r)), add_swap(x, p, r)),
          Equal.sym(Nat, Nat.add(p, 1n+Nat.add(x, r)), 1n+Nat.add(p, Nat.add(x, r)),
            M2.add_succ_r(p, Nat.add(x, r))))),
      e))

# rest is empty or starts with a line feed
def restf(rest: String) -> Type:
  Or({rest == SNil{} : String},
    Exists(Char, c => Exists(String, t =>
      Pair({rest == SCon{c, t} : String}, {D1.nl(c) == True{} : Bool}))))

# the block once a line has ended at k, with rest after: none, with
# whitespace from E up to k; or the text B from kp ending at k
def bclosed(T: String, cap: Nat, E: Nat, b: P.Block, k: Nat, rest: String) -> Type:
  match b:
    case P.Shut{}:
      M1.gap(T, E, k)
    case P.Open{psuf, pstart, pend, plen, room}:
      Exists(Nat, kp => Exists(String, B =>
        Pair({pstart == U32.from_nat(kp) : U32},
        Pair({String.drop(T, kp) == psuf : String},
        Pair({pend == U32.from_nat(Nat.add(plen, kp)) : U32},
        Pair({k == Nat.add(plen, kp) : Nat},
        Pair({Nat.add(plen, room) == cap : Nat},
        Pair({psuf == B ++ String.drop(T, Nat.add(plen, kp)) : String},
        Pair({String.length(B) == plen : Nat},
        Pair(M2.gapb(T, E, kp, B),
          {String.drop(T, Nat.add(plen, kp)) == rest : String}))))))))))

# good paragraphs out, tiled from E up to some E2, and a fact about E2
def outs(T: String, cap: Nat, E: Nat, out: List<&2, P.Para>, Z: Nat -> Type) -> Type:
  Pair(M3.all(T, cap, out), Exists(Nat, m => Pair(M2.tile(T, E, out, m), Z(m))))

# what a line's end at k gives
def endgood(+T: String, +cap: Nat, E: Nat, +k: Nat, +rest: String, e: P.Ended) -> Type:
  match e:
    case P.Ended{out, +b}:
      outs(T, cap, E, out, m => bclosed(T, cap, m, b, k, rest))

# what a code point gives the block, beside a line one longer
def growgood(+T: String, +cap: Nat, E: Nat, +kl: Nat, +llen: Nat, e: P.Ended) -> Type:
  match e:
    case P.Ended{out, +b}:
      outs(T, cap, E, out, m => M2.binv(T, cap, m, b, kl, 1n+llen))

# what a code point gives: good paragraphs, tiled, and a state keeping the
# invariant for what is left
def stepgood(+T: String, +cap: Nat, E: Nat, +t: String, s: P.Step) -> Type:
  match s:
    case P.Step{out, +next}:
      outs(T, cap, E, out, m => M2.inv(T, cap, m, t, next))

# pack an emission with the next state's fact
def pk(
  -T: String,
  -cap: Nat,
  -E: Nat,
  -out: List<&2, P.Para>,
  +M: Nat,
  -Z: Nat -> Type,
  r: Pair(M3.all(T, cap, out), M2.tile(T, E, out, M)),
  z: Z(M)
) -> outs(T, cap, E, out, Z):
  match r:
    case (a, t):
      (a, (M, (t, z)))

# --- emitting the block ---

# the block's paragraph from kp, with q from what lies past its line feed
def emit_blk.q(
  T: String,
  -cap: Nat,
  +E: Nat,
  +psuf: String,
  -pstart: U32,
  -pend: U32,
  +plen: Nat,
  -M: Nat,
  +kp: Nat,
  +B: String,
  es: {pstart == U32.from_nat(kp) : U32},
  edp: {String.drop(T, kp) == psuf : String},
  ee: {pend == U32.from_nat(Nat.add(plen, kp)) : U32},
  +d: Nat,
  edd: {Nat.add(plen, d) == cap : Nat},
  eb: {psuf == B ++ String.drop(T, Nat.add(plen, kp)) : String},
  elb: {String.length(B) == plen : Nat},
  ec: M3.endr(T, cap, Nat.add(plen, kp), B),
  g: M2.gapb(T, E, kp, B),
  tp: M2.tile(T, Nat.add(plen, kp), Nil{}, M),
  x: Exists(Nat, b => {Nat.add(Nat.add(plen, kp), 1n+b) == String.length(T) : Nat})
) -> Pair(M3.all(T, cap, P.Para.emit(psuf, pstart, pend, plen, Nil{})),
  M2.tile(T, E, P.Para.emit(psuf, pstart, pend, plen, Nil{}), M)):
  match g:
    case (gE, (nb1, nb2)):
      match x:
        case (b, eqq):
          M4.put(T, cap, E, psuf, pstart, pend, plen, Nil{}, M, kp, B, es, edp, ee, 1n+b,
            eqq, d, edd, eb, elb, ec, blk_full(B, nb1, nb2), gE, Unit{}, tp)

# the block's paragraph, ending at a line feed at m
def emit_blk(
  +T: String,
  -cap: Nat,
  +E: Nat,
  +psuf: String,
  -pstart: U32,
  -pend: U32,
  +plen: Nat,
  -M: Nat,
  +kp: Nat,
  +B: String,
  es: {pstart == U32.from_nat(kp) : U32},
  edp: {String.drop(T, kp) == psuf : String},
  ee: {pend == U32.from_nat(Nat.add(plen, kp)) : U32},
  +d: Nat,
  edd: {Nat.add(plen, d) == cap : Nat},
  eb: {psuf == B ++ String.drop(T, Nat.add(plen, kp)) : String},
  elb: {String.length(B) == plen : Nat},
  ec: M3.endr(T, cap, Nat.add(plen, kp), B),
  g: M2.gapb(T, E, kp, B),
  tp: M2.tile(T, Nat.add(plen, kp), Nil{}, M),
  -h: Char,
  -x: String,
  +edm: {String.drop(T, Nat.add(plen, kp)) == SCon{h, x} : String}
) -> Pair(M3.all(T, cap, P.Para.emit(psuf, pstart, pend, plen, Nil{})),
  M2.tile(T, E, P.Para.emit(psuf, pstart, pend, plen, Nil{}), M)):
  emit_blk.q(T, cap, E, psuf, pstart, pend, plen, M, kp, B, es, edp, ee, d, edd,
    eb, elb, ec, g, tp, M2.drop_len(T, Nat.add(plen, kp), h, x, edm))

# what follows the line feed at m is the line from kl == m + 1
def after_feed(
  +T: String,
  +m: Nat,
  -kl: Nat,
  -h: Char,
  -x: String,
  -lsuf: String,
  -A: String,
  -rest: String,
  +edm: {String.drop(T, m) == SCon{h, x} : String},
  ekl: {kl == 1n+m : Nat},
  eds: {String.drop(T, kl) == lsuf : String},
  ea: {lsuf == A ++ rest : String}
) -> {x == A ++ rest : String}:
  Equal.trans(String, x, String.drop(T, 1n+m), A ++ rest,
    Equal.sym(String, String.drop(T, 1n+m), x, M2.drop_step(T, m, h, x, edm)),
    Equal.trans(String, String.drop(T, 1n+m), lsuf, A ++ rest,
      (%ekl : {String.drop(T, _) == lsuf : String}; eds),
      ea))

# the first line of A then rest, rest empty or after a line feed, is A
def line_close(
  +A: String,
  -rest: String,
  +enl: {D1.nonl(A) == True{} : Bool},
  hr: restf(rest)
) -> {D1.line(A ++ rest) == A : String}:
  match hr:
    case Inl{e}:
      %Equal.sym(String, rest, SNil{}, e) : {D1.line(A ++ _) == A : String}
      Equal.trans(String, D1.line(A ++ SNil{}), D1.line(A), A,
        Equal.cong(String, String, z => D1.line(z), A ++ SNil{}, A, app_nil(A)),
        line_all(A, enl))
    case Inr{y}:
      match y:
        case (c, z):
          match z:
            case (t, w):
              match w:
                case (e, en):
                  %Equal.sym(String, rest, SCon{c, t}, e)
                    : {D1.line(A ++ _) == A : String}
                  line_stop(A, c, t, enl, en)

# the line's text A, from kl to k, as a gap when blank
def line_gap(
  -T: String,
  +kl: Nat,
  -k: Nat,
  -lsuf: String,
  +A: String,
  -rest: String,
  +llen: Nat,
  eds: {String.drop(T, kl) == lsuf : String},
  ea: {lsuf == A ++ rest : String},
  ed: {String.drop(T, k) == rest : String},
  ek: {k == Nat.add(llen, kl) : Nat},
  ela: {String.length(A) == llen : Nat},
  eb: {D1.blank(A) == True{} : Bool}
) -> M1.gap(T, kl, k):
  (A, (Equal.trans(String, String.drop(T, kl), lsuf, A ++ String.drop(T, k), eds,
      Equal.trans(String, lsuf, A ++ rest, A ++ String.drop(T, k), ea,
        Equal.cong(String, String, z => A ++ z, rest, String.drop(T, k),
          Equal.sym(String, String.drop(T, k), rest, ed)))),
    (Equal.trans(Nat, Nat.add(kl, String.length(A)), Nat.add(llen, kl), k,
      Equal.trans(Nat, Nat.add(kl, String.length(A)), Nat.add(kl, llen),
        Nat.add(llen, kl),
        Equal.cong(Nat, Nat, z => Nat.add(kl, z), String.length(A), llen, ela),
        M2.add_comm(kl, llen)),
      Equal.sym(Nat, k, Nat.add(llen, kl), ek)), eb)))

# the line feed at m is a gap up to kl == m + 1
def feed_gap(
  +T: String,
  +m: Nat,
  -kl: Nat,
  +h: Char,
  -x: String,
  +edm: {String.drop(T, m) == SCon{h, x} : String},
  enh: {D1.nl(h) == True{} : Bool},
  ekl: {kl == 1n+m : Nat}
) -> M1.gap(T, m, kl):
  %Equal.sym(Nat, kl, 1n+m, ekl) : M1.gap(T, m, _)
  gap_one(T, m, h, x, edm, nl_space(h, enh))

# --- a line's end ---

# a line from kl to k, of llen code points, as a block of its own
def open_line(
  -T: String,
  -cap: Nat,
  -E: Nat,
  -rest: String,
  -off: U32,
  -lsuf: String,
  -lstart: U32,
  -llen: Nat,
  -lroom: Nat,
  -k: Nat,
  +kl: Nat,
  +A: String,
  eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == rest : String},
  el: {lstart == U32.from_nat(kl) : U32},
  eds: {String.drop(T, kl) == lsuf : String},
  +ek: {k == Nat.add(llen, kl) : Nat},
  er: {Nat.add(llen, lroom) == cap : Nat},
  ea: {lsuf == A ++ rest : String},
  ela: {String.length(A) == llen : Nat},
  +enl: {D1.nonl(A) == True{} : Bool},
  eim: {D1.blank(A) == False{} : Bool},
  g: M1.gap(T, E, kl)
) -> bclosed(T, cap, E, P.Open{lsuf, lstart, off, llen, lroom}, k, rest):
  (kl, (A, (el, (eds,
    (Equal.trans(U32, off, U32.from_nat(k), U32.from_nat(Nat.add(llen, kl)), eo,
      Equal.cong(Nat, U32, x => U32.from_nat(x), k, Nat.add(llen, kl), ek)),
    (ek, (er,
    (Equal.trans(String, lsuf, A ++ rest, A ++ String.drop(T, Nat.add(llen, kl)),
      ea, Equal.cong(String, String, z => A ++ z, rest,
        String.drop(T, Nat.add(llen, kl)),
        Equal.sym(String, String.drop(T, Nat.add(llen, kl)), rest,
          (%ek : {String.drop(T, _) == rest : String}; ed)))),
    (ela, ((g, ((%Equal.sym(String, D1.line(A), A, line_nonl(A, enl))
        : {D1.blank(_) == False{} : Bool}; eim), fed_nonl(A, enl))),
      (%ek : {String.drop(T, _) == rest : String}; ed)))))))))))

# a line that does not fit beside the block: with the next line, the block
# would be longer than cap
def lt_feed0(
  -cap: Nat,
  -B: String,
  -x: String,
  +A: String,
  +plen: Nat,
  +llen: Nat,
  eline: {D1.line(x) == A : String},
  ela: {String.length(A) == llen : Nat},
  elb: {String.length(B) == plen : Nat},
  erm: {Nat.add(plen, Nat.add(llen, 0n)) == cap : Nat}
) -> {Nat.is_lt(cap, Nat.add(String.length(B), 1n+String.length(D1.line(x))))
  == True{} : Bool}:
  %Equal.sym(String, D1.line(x), A, eline)
    : {Nat.is_lt(cap, Nat.add(String.length(B), 1n+String.length(_))) == True{} : Bool}
  %Equal.sym(Nat, String.length(A), llen, ela)
    : {Nat.is_lt(cap, Nat.add(String.length(B), 1n+_)) == True{} : Bool}
  %Equal.sym(Nat, String.length(B), plen, elb)
    : {Nat.is_lt(cap, Nat.add(_, 1n+llen)) == True{} : Bool}
  %erm : {Nat.is_lt(_, Nat.add(plen, 1n+llen)) == True{} : Bool}
  lt_room0(plen, llen)

# the text of a block joined by a line: B, the line feed h, then A
def join_text(
  -T: String,
  -psuf: String,
  +B: String,
  +h: Char,
  -x: String,
  +A: String,
  -rest: String,
  +m: Nat,
  -m2: Nat,
  eb: {psuf == B ++ String.drop(T, m) : String},
  edm: {String.drop(T, m) == SCon{h, x} : String},
  xeq: {x == A ++ rest : String},
  edr: {String.drop(T, m2) == rest : String}
) -> {psuf == (B ++ SCon{h, A}) ++ String.drop(T, m2) : String}:
  Equal.trans(String, psuf, B ++ String.drop(T, m), (B ++ SCon{h, A}) ++ String.drop(T, m2),
    eb,
    Equal.trans(String, B ++ String.drop(T, m), B ++ SCon{h, A ++ rest},
      (B ++ SCon{h, A}) ++ String.drop(T, m2),
      Equal.cong(String, String, z => B ++ z, String.drop(T, m), SCon{h, A ++ rest},
        Equal.trans(String, String.drop(T, m), SCon{h, x}, SCon{h, A ++ rest}, edm,
          Equal.cong(String, String, z => SCon{h, z}, x, A ++ rest, xeq))),
      Equal.trans(String, B ++ SCon{h, A ++ rest}, (B ++ SCon{h, A}) ++ rest,
        (B ++ SCon{h, A}) ++ String.drop(T, m2),
        Equal.sym(String, (B ++ SCon{h, A}) ++ rest, B ++ SCon{h, A ++ rest},
          M4.app_assoc(B, SCon{h, A}, rest)),
        Equal.cong(String, String, z => (B ++ SCon{h, A}) ++ z, rest,
          String.drop(T, m2), Equal.sym(String, String.drop(T, m2), rest, edr)))))

# the length of a block joined by a line
def join_len(
  +B: String,
  -h: Char,
  +A: String,
  +plen: Nat,
  +llen: Nat,
  elb: {String.length(B) == plen : Nat},
  ela: {String.length(A) == llen : Nat}
) -> {String.length(B ++ SCon{h, A}) == Nat.add(llen, 1n+plen) : Nat}:
  Equal.trans(Nat, String.length(B ++ SCon{h, A}),
    Nat.add(String.length(B), 1n+String.length(A)), Nat.add(llen, 1n+plen),
    M4.len_app(B, SCon{h, A}),
    Equal.trans(Nat, Nat.add(String.length(B), 1n+String.length(A)),
      Nat.add(plen, 1n+llen), Nat.add(llen, 1n+plen),
      (%elb : {Nat.add(String.length(B), 1n+String.length(A)) == Nat.add(_, 1n+llen) : Nat};
        %ela : {Nat.add(String.length(B), 1n+String.length(A))
          == Nat.add(String.length(B), 1n+_) : Nat}; {==}),
      add_flip(plen, llen)))

# B joined by the line A after h: its first line is not blank, and every
# line feed is followed by a full line
def jnb(B: String, h: Char, A: String) -> Type:
  Pair({D1.blank(D1.line(B ++ SCon{h, A})) == False{} : Bool},
    {L1.fedok(B ++ SCon{h, A}) == True{} : Bool})

# a block's text B joined by the line A after the line feed h keeps its
# lines full, when A is not blank
def join_nb(
  +B: String,
  +h: Char,
  +A: String,
  nb1: {D1.blank(D1.line(B)) == False{} : Bool},
  nb2: {L1.fedok(B) == True{} : Bool},
  +enh: {D1.nl(h) == True{} : Bool},
  +enl: {D1.nonl(A) == True{} : Bool},
  eim: {D1.blank(A) == False{} : Bool}
) -> jnb(B, h, A):
  ((%Equal.sym(String, D1.line(B ++ SCon{h, A}), D1.line(B), line_feed(B, h, A, enh))
      : {D1.blank(_) == False{} : Bool}; nb1),
    fed_join(B, h, A, enh, enl, eim, nb2))

# the block extended by a line, with the facts on its new text
def join_ext2(
  +T: String,
  -cap: Nat,
  +E: Nat,
  -rest: String,
  -off: U32,
  -psuf: String,
  -pstart: U32,
  +plen: Nat,
  +llen: Nat,
  +r: Nat,
  -k: Nat,
  +kp: Nat,
  +B: String,
  +h: Char,
  +A: String,
  eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == rest : String},
  es: {pstart == U32.from_nat(kp) : U32},
  edp: {String.drop(T, kp) == psuf : String},
  gE: M1.gap(T, E, kp),
  nbs: jnb(B, h, A),
  erm: {Nat.add(plen, Nat.add(llen, 1n+r)) == cap : Nat},
  ela: {String.length(A) == llen : Nat},
  elb: {String.length(B) == plen : Nat},
  +K: {k == Nat.add(Nat.add(llen, 1n+plen), kp) : Nat},
  -x: String,
  eb: {psuf == B ++ String.drop(T, Nat.add(plen, kp)) : String},
  edm: {String.drop(T, Nat.add(plen, kp)) == SCon{h, x} : String},
  xeq: {x == A ++ rest : String}
) -> outs(T, cap, E, Nil{}, m => bclosed(T, cap, m,
  P.Open{psuf, pstart, off, Nat.add(llen, 1n+plen), r}, k, rest)):
  (Unit{}, (E, (gap_nil(T, E),
    (kp, (B ++ SCon{h, A}, (es, (edp,
      (Equal.trans(U32, off, U32.from_nat(k),
        U32.from_nat(Nat.add(Nat.add(llen, 1n+plen), kp)), eo,
        Equal.cong(Nat, U32, z => U32.from_nat(z), k,
          Nat.add(Nat.add(llen, 1n+plen), kp), K)),
      (K,
      (Equal.trans(Nat, Nat.add(Nat.add(llen, 1n+plen), r),
        Nat.add(plen, Nat.add(llen, 1n+r)), cap, add_join(llen, plen, r), erm),
      (join_text(T, psuf, B, h, x, A, rest, Nat.add(plen, kp),
        Nat.add(Nat.add(llen, 1n+plen), kp), eb, edm, xeq,
        (%K : {String.drop(T, _) == rest : String}; ed)),
      (join_len(B, h, A, plen, llen, elb, ela),
      ((gE, nbs), (%K : {String.drop(T, _) == rest : String}; ed))))))))))))))

# the block extended by a line ending at k: K says where k is
def join_ext(
  +T: String,
  -cap: Nat,
  +E: Nat,
  -rest: String,
  -off: U32,
  -psuf: String,
  -pstart: U32,
  +plen: Nat,
  +llen: Nat,
  +r: Nat,
  -k: Nat,
  +kp: Nat,
  +B: String,
  +h: Char,
  +A: String,
  eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == rest : String},
  es: {pstart == U32.from_nat(kp) : U32},
  edp: {String.drop(T, kp) == psuf : String},
  g: M2.gapb(T, E, kp, B),
  erm: {Nat.add(plen, Nat.add(llen, 1n+r)) == cap : Nat},
  ela: {String.length(A) == llen : Nat},
  elb: {String.length(B) == plen : Nat},
  +K: {k == Nat.add(Nat.add(llen, 1n+plen), kp) : Nat},
  -x: String,
  eb: {psuf == B ++ String.drop(T, Nat.add(plen, kp)) : String},
  edm: {String.drop(T, Nat.add(plen, kp)) == SCon{h, x} : String},
  xeq: {x == A ++ rest : String},
  +enh: {D1.nl(h) == True{} : Bool},
  +enl: {D1.nonl(A) == True{} : Bool},
  eim: {D1.blank(A) == False{} : Bool}
) -> outs(T, cap, E, Nil{}, m => bclosed(T, cap, m,
  P.Open{psuf, pstart, off, Nat.add(llen, 1n+plen), r}, k, rest)):
  match g:
    case (gE, (nb1, nb2)):
      join_ext2(T, cap, E, rest, off, psuf, pstart, plen, llen, r, k, kp, B, h, A, eo, ed,
        es, edp, gE, join_nb(B, h, A, nb1, nb2, enh, enl, eim), erm, ela, elb, K, x, eb, edm, xeq)

# a non-blank line's end keeps the invariant
def join_ok(
  +T: String,
  +cap: Nat,
  +E: Nat,
  +rest: String,
  +off: U32,
  b: P.Block,
  +lsuf: String,
  +lstart: U32,
  +llen: Nat,
  +lroom: Nat,
  +k: Nat,
  +kl: Nat,
  +A: String,
  +eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == rest : String},
  +el: {lstart == U32.from_nat(kl) : U32},
  +eds: {String.drop(T, kl) == lsuf : String},
  +ek: {k == Nat.add(llen, kl) : Nat},
  +er: {Nat.add(llen, lroom) == cap : Nat},
  +ea: {lsuf == A ++ rest : String},
  +ela: {String.length(A) == llen : Nat},
  +enl: {D1.nonl(A) == True{} : Bool},
  eim: {D1.blank(A) == False{} : Bool},
  bi: M2.binv(T, cap, E, b, kl, llen),
  hr: restf(rest)
) -> endgood(T, cap, E, k, rest, P.Para.close.join(off, b, lsuf, lstart, llen, lroom)):
  match b:
    case P.Shut{}:
      (Unit{}, (E, (gap_nil(T, E), open_line(T, cap, E, rest, off, lsuf, lstart, llen,
        lroom, k, kl, A, eo, ed, el, eds, ek, er, ea, ela, enl, eim, bi))))
    case P.Open{+psuf, +pstart, +pend, +plen, room}:
      match room:
        case 0n:
          match bi:
            case (+kp, (+B, (es, (edp, (ee, (+ekl, (+erm, (eb, (+elb, (g, ef)))))))))):
              match ef:
                case (+h, (+x, (+edm, +enh))):
                  pk(T, cap, E, P.Para.emit(psuf, pstart, pend, plen, Nil{}), kl,
                    m => bclosed(T, cap, m, P.Open{lsuf, lstart, off, llen, lroom}, k, rest),
                    emit_blk(T, cap, E, psuf, pstart, pend, plen, kl, kp, B, es, edp, ee,
                      Nat.add(llen, 0n), erm, eb, elb,
                      Inr{Inl{(h, (x, (edm, (enh, lt_feed0(cap, B, x, A, plen, llen,
                        Equal.trans(String, D1.line(x), D1.line(A ++ rest), A,
                          Equal.cong(String, String, z => D1.line(z), x, A ++ rest,
                            after_feed(T, Nat.add(plen, kp), kl, h, x, lsuf, A, rest,
                              edm, ekl, eds, ea)),
                          line_close(A, rest, enl, hr)),
                        ela, elb, erm)))))}},
                      g, feed_gap(T, Nat.add(plen, kp), kl, h, x, edm, enh, ekl), h, x, edm),
                    open_line(T, cap, kl, rest, off, lsuf, lstart, llen, lroom, k, kl, A,
                      eo, ed, el, eds, ek, er, ea, ela, enl, eim, gap_nil(T, kl)))
        case 1n+r:
          match bi:
            case (+kp, (+B, (es, (edp, (ee, (+ekl, (erm, (eb, (+elb, (g, ef)))))))))):
              match ef:
                case (+h, (+x, (+edm, +enh))):
                  join_ext(T, cap, E, rest, off, psuf, pstart, plen, llen, r, k, kp, B, h, A,
                    eo, ed, es, edp, g, erm, ela, elb,
                    Equal.trans(Nat, k, Nat.add(llen, kl),
                      Nat.add(Nat.add(llen, 1n+plen), kp), ek,
                      Equal.trans(Nat, Nat.add(llen, kl),
                        Nat.add(llen, 1n+Nat.add(plen, kp)),
                        Nat.add(Nat.add(llen, 1n+plen), kp),
                        Equal.cong(Nat, Nat, z => Nat.add(llen, z), kl,
                          1n+Nat.add(plen, kp), ekl),
                        Equal.sym(Nat, Nat.add(Nat.add(llen, 1n+plen), kp),
                          Nat.add(llen, 1n+Nat.add(plen, kp)),
                          M2.add_assoc(llen, 1n+plen, kp)))),
                    x, eb, edm,
                    after_feed(T, Nat.add(plen, kp), kl, h, x, lsuf, A, rest, edm, ekl,
                      eds, ea), enh, enl, eim)

# a true Bool, twice
def tru2(b: Bool, e: {b == True{} : Bool}) -> Pair({b == True{} : Bool}, {b == True{} : Bool}):
  match b:
    case False{}:
      Empty.absurd(Pair({False{} == True{} : Bool}, {False{} == True{} : Bool}), M1.clash(e))
    case True{}:
      ({==}, {==})

# a blank line's text A, with rest empty or starting at a line feed, makes
# x == A ++ rest a blank first line
def flush_line(
  +x: String,
  +A: String,
  -rest: String,
  xeq: {x == A ++ rest : String},
  +enl: {D1.nonl(A) == True{} : Bool},
  e1: {D1.blank(A) == True{} : Bool},
  hr: restf(rest)
) -> {D1.blank(D1.line(x)) == True{} : Bool}:
  %Equal.sym(String, x, A ++ rest, xeq) : {D1.blank(D1.line(_)) == True{} : Bool}
  %Equal.sym(String, D1.line(A ++ rest), A, line_close(A, rest, enl, hr))
    : {D1.blank(_) == True{} : Bool}
  e1

# a block's run ending at the line feed h at m, before a blank line A: at
# the end of T only whitespace is left, else another line feed follows
def flush_end(
  +T: String,
  +m: Nat,
  +h: Char,
  +x: String,
  +A: String,
  -rest: String,
  +edm: {String.drop(T, m) == SCon{h, x} : String},
  +enh: {D1.nl(h) == True{} : Bool},
  +xeq: {x == A ++ rest : String},
  +enl: {D1.nonl(A) == True{} : Bool},
  +e1: {D1.blank(A) == True{} : Bool},
  hr: restf(rest)
) -> M3.endl(T, m):
  match hr:
    case Inl{+er}:
      Inl{(
        (%Equal.sym(String, String.drop(T, m), SCon{h, x}, edm)
            : {D1.blank(_) == True{} : Bool}
          %Equal.sym(String, x, A ++ rest, xeq)
            : {Bool.and(Char.is_space(h), D1.blank(_)) == True{} : Bool}
          %Equal.sym(String, rest, SNil{}, er)
            : {Bool.and(Char.is_space(h), D1.blank(A ++ _)) == True{} : Bool}
          %Equal.sym(String, A ++ "", A, app_nil(A))
            : {Bool.and(Char.is_space(h), D1.blank(_)) == True{} : Bool}
          %Equal.sym(Bool, D1.blank(A), True{}, e1)
            : {Bool.and(Char.is_space(h), _) == True{} : Bool}
          %Equal.sym(Bool, Char.is_space(h), True{}, nl_space(h, enh))
            : {Bool.and(_, True{}) == True{} : Bool}
          {==}),
        Inr{(h, (x, (edm, (enh, flush_line(x, A, rest, xeq, enl, e1, Inl{er})))))})}
    case Inr{f}:
      match f:
        case (+c, (+t, (+er, +enc))):
          Inr{(h, (x, (edm, (enh,
            (flush_line(x, A, rest, xeq, enl, e1, Inr{(c, (t, (er, enc)))}),
              (%Equal.sym(String, x, A ++ rest, xeq) : {D1.nonl(_) == False{} : Bool}
                %Equal.sym(String, rest, SCon{c, t}, er)
                  : {D1.nonl(A ++ _) == False{} : Bool}
                nonl_feed(A, c, t, enc)))))))}

# a blank line's end flushes the block, which ends its run there
def blank_flush(
  +T: String,
  +cap: Nat,
  +E: Nat,
  b: P.Block,
  +kl: Nat,
  +k: Nat,
  +lsuf: String,
  +A: String,
  +rest: String,
  +llen: Nat,
  +eds: {String.drop(T, kl) == lsuf : String},
  +ea: {lsuf == A ++ rest : String},
  +enl: {D1.nonl(A) == True{} : Bool},
  ed: {String.drop(T, k) == rest : String},
  ek: {k == Nat.add(llen, kl) : Nat},
  ela: {String.length(A) == llen : Nat},
  bi: M2.binv(T, cap, E, b, kl, llen),
  hr: restf(rest),
  eb2: Pair({D1.blank(A) == True{} : Bool}, {D1.blank(A) == True{} : Bool})
) -> outs(T, cap, E, P.Para.flush(b, Nil{}), m => M1.gap(T, m, k)):
  match b:
    case P.Shut{}:
      match eb2:
        case (e1, _e2):
          (Unit{}, (k, (M4.gap_cat(T, E, kl, k, bi,
            line_gap(T, kl, k, lsuf, A, rest, llen, eds, ea, ed, ek, ela, e1)),
            gap_nil(T, k))))
    case P.Open{+psuf, +pstart, +pend, +plen, +room}:
      match bi:
        case (+kp, (+B, (es, (edp, (ee, (+ekl, (erm, (eb, (elb, (g, ef)))))))))):
          match ef:
            case (+h, (+x, (+edm, +enh))):
              match eb2:
                case (e1, e2):
                  pk(T, cap, E, P.Para.emit(psuf, pstart, pend, plen, Nil{}), k,
                    m => M1.gap(T, m, k),
                    emit_blk(T, cap, E, psuf, pstart, pend, plen, k, kp, B, es, edp, ee,
                      Nat.add(llen, room), erm, eb, elb,
                      Inl{flush_end(T, Nat.add(plen, kp), h, x, A, rest, edm, enh,
                        after_feed(T, Nat.add(plen, kp), kl, h, x, lsuf, A, rest, edm,
                          ekl, eds, ea),
                        enl, e1, hr)},
                      g,
                      M4.gap_cat(T, Nat.add(plen, kp), kl, k,
                        feed_gap(T, Nat.add(plen, kp), kl, h, x, edm, enh, ekl),
                        line_gap(T, kl, k, lsuf, A, rest, llen, eds, ea, ed, ek, ela, e2)),
                      h, x, edm),
                    gap_nil(T, k))

# a line's end keeps the invariant
def close_ok(
  +T: String,
  +cap: Nat,
  +E: Nat,
  +rest: String,
  +off: U32,
  b: P.Block,
  ln: P.Line,
  +k: Nat,
  +kl: Nat,
  +eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == rest : String},
  lf: M2.lfacts(T, cap, k, kl, rest, ln),
  bi: M2.binv(T, cap, E, b, kl, M2.lenof(ln)),
  hr: restf(rest)
) -> endgood(T, cap, E, k, rest, P.Para.close(off, b, ln)):
  match ln:
    case P.Line{+lsuf, +lstart, +llen, +lroom, flag}:
      match flag:
        case True{}:
          match lf:
            case (+A, (_el, (+eds, (+ek, (_er, (+ea, (+ela, (+enl, ebA)))))))):
              blank_flush(T, cap, E, b, kl, k, lsuf, A, rest, llen, eds, ea, enl, ed,
                ek, ela, bi, hr, tru2(D1.blank(A), ebA))
        case False{}:
          match lf:
            case (+A, (el, (eds, (ek, (er, (ea, (ela, (enl, eim)))))))):
              join_ok(T, cap, E, rest, off, b, lsuf, lstart, llen, lroom, k, kl, A,
                eo, ed, el, eds, ek, er, ea, ela, enl, eim, bi, hr)

# --- one code point ---

# one code point on: k + 1 and what is left after it still make up T
def en_step(
  -T: String,
  k: Nat,
  t: String,
  en: {Nat.add(k, 1n+String.length(t)) == String.length(T) : Nat}
) -> {Nat.add(1n+k, String.length(t)) == String.length(T) : Nat}:
  Equal.trans(Nat, 1n+Nat.add(k, String.length(t)),
    Nat.add(k, 1n+String.length(t)), String.length(T),
    Equal.sym(Nat, Nat.add(k, 1n+String.length(t)),
      1n+Nat.add(k, String.length(t)), M2.add_succ_r(k, String.length(t))), en)

# a block closed at a line feed at k, ready beside the next line at k + 1
def bclose_nl(
  +T: String,
  -cap: Nat,
  +E: Nat,
  b: P.Block,
  +k: Nat,
  +c: Char,
  +t: String,
  +ed: {String.drop(T, k) == SCon{c, t} : String},
  +enc: {D1.nl(c) == True{} : Bool},
  bc: bclosed(T, cap, E, b, k, SCon{c, t})
) -> M2.binv(T, cap, E, b, 1n+k, 0n):
  match b:
    case P.Shut{}:
      M4.gap_cat(T, E, k, 1n+k, bc, gap_one(T, k, c, t, ed, nl_space(c, enc)))
    case P.Open{_psuf, _pstart, _pend, plen, _room}:
      match bc:
        case (kp, (B, (es, (edp, (ee, (ekm, (erm, (eb, (elb, (g, edr)))))))))):
          (kp, (B, (es, (edp, (ee,
            (Equal.cong(Nat, Nat, z => 1n+z, k, Nat.add(plen, kp), ekm),
            (erm, (eb, (elb, (g, (c, (t, (edr, enc)))))))))))))

# a line feed at k: the line ends, and the next starts after it
def nl_ok(
  +T: String,
  +cap: Nat,
  -E: Nat,
  +off: U32,
  +c: Char,
  +t: String,
  e: P.Ended,
  +k: Nat,
  +eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == SCon{c, t} : String},
  en: {Nat.add(k, 1n+String.length(t)) == String.length(T) : Nat},
  enc: {D1.nl(c) == True{} : Bool},
  he: endgood(T, cap, E, k, SCon{c, t}, e)
) -> stepgood(T, cap, E, t, P.Para.step.nl(cap, off, t, e)):
  match e:
    case P.Ended{_out, b2}:
      match he:
        case (a, z):
          match z:
            case (+E2, w):
              match w:
                case (tl, bc):
                  (a, (E2, (tl, (1n+k, (1n+k,
                    (Equal.cong(U32, U32, x => U32.inc(x), off, U32.from_nat(k), eo),
                    (M2.drop_step(T, k, c, t, ed), (en_step(T, k, t, en),
                    ((SNil{},
                      (Equal.cong(U32, U32, x => U32.inc(x), off, U32.from_nat(k), eo),
                      (M2.drop_step(T, k, c, t, ed),
                      ({==}, ({==}, ({==}, ({==}, ({==}, {==})))))))),
                    bclose_nl(T, cap, E2, b2, k, c, t, ed, enc, bc))))))))))

# and with True on the right changes nothing
def and_true(b: Bool) -> {Bool.and(b, True{}) == b : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

# a ++ b is blank exactly when both are
def blank_app_eq(
  a: String,
  -b: String
) -> {D1.blank(a ++ b) == Bool.and(D1.blank(a), D1.blank(b)) : Bool}:
  match a:
    case SNil{}:
      {==}
    case SCon{+h, t}:
      Equal.trans(Bool, Bool.and(Char.is_space(h), D1.blank(t ++ b)),
        Bool.and(Char.is_space(h), Bool.and(D1.blank(t), D1.blank(b))),
        Bool.and(Bool.and(Char.is_space(h), D1.blank(t)), D1.blank(b)),
        Equal.cong(Bool, Bool, z => Bool.and(Char.is_space(h), z), D1.blank(t ++ b),
          Bool.and(D1.blank(t), D1.blank(b)), blank_app_eq(t, b)),
        and_assoc(Char.is_space(h), D1.blank(t), D1.blank(b)))

# a line one code point longer is blank exactly when it was and c is
def blank_grow(
  +A: String,
  +c: Char,
  -flag: Bool,
  e: {D1.blank(A) == flag : Bool}
) -> {D1.blank(A ++ SCon{c, SNil{}}) == Bool.and(flag, Char.is_space(c)) : Bool}:
  %e : {D1.blank(A ++ SCon{c, SNil{}}) == Bool.and(_, Char.is_space(c)) : Bool}
  Equal.trans(Bool, D1.blank(A ++ SCon{c, SNil{}}),
    Bool.and(D1.blank(A), Bool.and(Char.is_space(c), True{})),
    Bool.and(D1.blank(A), Char.is_space(c)), blank_app_eq(A, SCon{c, SNil{}}),
    Equal.cong(Bool, Bool, z => Bool.and(D1.blank(A), z),
      Bool.and(Char.is_space(c), True{}), Char.is_space(c), and_true(Char.is_space(c))))

# a code point c that is no line feed, joining a line of A beside a block
# of plen with room r of 0 or 1 left (r + m == 2 + the rest of the line):
# with its whole line the block would be longer than cap
def lt_cut(
  -cap: Nat,
  -B: String,
  -x: String,
  +A: String,
  +c: Char,
  +t: String,
  +plen: Nat,
  +llen: Nat,
  +r: Nat,
  +m: Nat,
  xeq: {x == A ++ SCon{c, t} : String},
  enl: {D1.nonl(A) == True{} : Bool},
  ec: {D1.nl(c) == False{} : Bool},
  ela: {String.length(A) == llen : Nat},
  elb: {String.length(B) == plen : Nat},
  erm: {Nat.add(plen, Nat.add(llen, r)) == cap : Nat},
  em: {Nat.add(r, 1n+m) == 1n+1n+String.length(D1.line(t)) : Nat}
) -> {Nat.is_lt(cap, Nat.add(String.length(B), 1n+String.length(D1.line(x))))
  == True{} : Bool}:
  %Equal.sym(String, x, A ++ SCon{c, t}, xeq)
    : {Nat.is_lt(cap, Nat.add(String.length(B), 1n+String.length(D1.line(_))))
      == True{} : Bool}
  %Equal.sym(String, D1.line(A ++ SCon{c, t}), A ++ SCon{c, D1.line(t)},
      line_go(A, c, t, enl, ec))
    : {Nat.is_lt(cap, Nat.add(String.length(B), 1n+String.length(_))) == True{} : Bool}
  %Equal.sym(Nat, String.length(A ++ SCon{c, D1.line(t)}),
      Nat.add(String.length(A), 1n+String.length(D1.line(t))),
      M4.len_app(A, SCon{c, D1.line(t)}))
    : {Nat.is_lt(cap, Nat.add(String.length(B), 1n+_)) == True{} : Bool}
  %Equal.sym(Nat, String.length(A), llen, ela)
    : {Nat.is_lt(cap, Nat.add(String.length(B),
      1n+Nat.add(_, 1n+String.length(D1.line(t))))) == True{} : Bool}
  %Equal.sym(Nat, String.length(B), plen, elb)
    : {Nat.is_lt(cap, Nat.add(_, 1n+Nat.add(llen, 1n+String.length(D1.line(t)))))
      == True{} : Bool}
  %erm : {Nat.is_lt(_, Nat.add(plen, 1n+Nat.add(llen, 1n+String.length(D1.line(t)))))
      == True{} : Bool}
  %M2.add_succ_r(llen, 1n+String.length(D1.line(t)))
    : {Nat.is_lt(Nat.add(plen, Nat.add(llen, r)), Nat.add(plen, _)) == True{} : Bool}
  %em : {Nat.is_lt(Nat.add(plen, Nat.add(llen, r)), Nat.add(plen, Nat.add(llen, _)))
    == True{} : Bool}
  lt_gen(plen, llen, r, m)

# a code point read while a block is open keeps the block's invariant
# beside a line one longer, or finishes the block where the line would not
# fit
def gb_ok(
  +T: String,
  +cap: Nat,
  +E: Nat,
  b: P.Block,
  +kl: Nat,
  +llen: Nat,
  +lsuf: String,
  +A: String,
  +c: Char,
  +t: String,
  +eds: {String.drop(T, kl) == lsuf : String},
  +ea: {lsuf == A ++ SCon{c, t} : String},
  +ela: {String.length(A) == llen : Nat},
  +enl: {D1.nonl(A) == True{} : Bool},
  +ec: {D1.nl(c) == False{} : Bool},
  bi: M2.binv(T, cap, E, b, kl, llen)
) -> growgood(T, cap, E, kl, llen, P.Para.grow.block(b)):
  match b:
    case P.Shut{}:
      (Unit{}, (E, (gap_nil(T, E), bi)))
    case P.Open{+psuf, +pstart, +pend, +plen, room}:
      match room:
        case 0n:
          match bi:
            case (+kp, (+B, (es, (edp, (ee, (+ekl, (+erm, (eb, (+elb, (g, ef)))))))))):
              match ef:
                case (+h, (+x, (+edm, +enh))):
                  pk(T, cap, E, P.Para.emit(psuf, pstart, pend, plen, Nil{}), kl,
                    m => M2.binv(T, cap, m, P.Shut{}, kl, 1n+llen),
                    emit_blk(T, cap, E, psuf, pstart, pend, plen, kl, kp, B, es, edp, ee,
                      Nat.add(llen, 0n), erm, eb, elb,
                      Inr{Inl{(h, (x, (edm, (enh,
                        lt_cut(cap, B, x, A, c, t, plen, llen, 0n, 1n+String.length(D1.line(t)),
                          after_feed(T, Nat.add(plen, kp), kl, h, x, lsuf, A, SCon{c, t},
                            edm, ekl, eds, ea),
                          enl, ec, ela, elb, erm, {==})))))}},
                      g, feed_gap(T, Nat.add(plen, kp), kl, h, x, edm, enh, ekl), h, x, edm),
                    gap_nil(T, kl))
        case 1n+0n:
          match bi:
            case (+kp, (+B, (es, (edp, (ee, (+ekl, (+erm, (eb, (+elb, (g, ef)))))))))):
              match ef:
                case (+h, (+x, (+edm, +enh))):
                  pk(T, cap, E, P.Para.emit(psuf, pstart, pend, plen, Nil{}), kl,
                    m => M2.binv(T, cap, m, P.Shut{}, kl, 1n+llen),
                    emit_blk(T, cap, E, psuf, pstart, pend, plen, kl, kp, B, es, edp, ee,
                      Nat.add(llen, 1n), erm, eb, elb,
                      Inr{Inl{(h, (x, (edm, (enh,
                        lt_cut(cap, B, x, A, c, t, plen, llen, 1n, String.length(D1.line(t)),
                          after_feed(T, Nat.add(plen, kp), kl, h, x, lsuf, A, SCon{c, t},
                            edm, ekl, eds, ea),
                          enl, ec, ela, elb, erm, {==})))))}},
                      g, feed_gap(T, Nat.add(plen, kp), kl, h, x, edm, enh, ekl), h, x, edm),
                    gap_nil(T, kl))
        case 1n+1n+r:
          match bi:
            case (kp, (B, (es, (edp, (ee, (ekl, (erm, (eb, (elb, (g, ef)))))))))):
              (Unit{}, (E, (gap_nil(T, E), (kp, (B, (es, (edp, (ee, (ekl,
                (Equal.trans(Nat, Nat.add(plen, 1n+Nat.add(llen, 1n+r)),
                  Nat.add(plen, Nat.add(llen, 1n+1n+r)), cap,
                  Equal.sym(Nat, Nat.add(plen, Nat.add(llen, 1n+1n+r)),
                    Nat.add(plen, 1n+Nat.add(llen, 1n+r)),
                    Equal.cong(Nat, Nat, z => Nat.add(plen, z),
                      Nat.add(llen, 1n+1n+r), 1n+Nat.add(llen, 1n+r),
                      M2.add_succ_r(llen, 1n+r))),
                  erm),
                (eb, (elb, (g, ef)))))))))))))

# the rest of a line cut at the limit starts a new line at k
def cut_ok(
  +T: String,
  cap: Nat,
  -c0: Nat,
  hcap: {cap == 1n+c0 : Nat},
  E: Nat,
  -E2: Nat,
  +off: U32,
  +c: Char,
  +t: String,
  +out: List<&2, P.Para>,
  em: List<&2, P.Para>,
  +k: Nat,
  +eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == SCon{c, t} : String},
  en: {Nat.add(k, 1n+String.length(t)) == String.length(T) : Nat},
  ec: {D1.nl(c) == False{} : Bool},
  a: M3.all(T, cap, out),
  tl: M2.tile(T, E, out, E2),
  r: Pair(M3.all(T, cap, em), M2.tile(T, E2, em, k))
) -> stepgood(T, cap, E, t, P.Para.grow.cut(cap, off, c, t,
  List.append(&2, P.Para, out, em))):
  match cap:
    case 0n:
      Empty.absurd(stepgood(T, 0n, E, t, P.Para.grow.cut(0n, off, c, t,
          List.append(&2, P.Para, out, em))),
        M2.succ_ne_zero(c0, Equal.sym(Nat, 0n, 1n+c0, hcap)))
    case 1n+_r0:
      match r:
        case (a2, t2):
          (all_append(T, cap, out, em, a, a2), (k,
            (tile_app(out, T, E, E2, em, k, tl, t2),
            (1n+k, (k,
              (Equal.cong(U32, U32, x => U32.inc(x), off, U32.from_nat(k), eo),
              (M2.drop_step(T, k, c, t, ed), (en_step(T, k, t, en),
              ((SCon{c, SNil{}}, (eo, (ed, ({==}, ({==}, ({==}, ({==},
                (nonl_one(c, ec), and_true(Char.is_space(c)))))))))),
              gap_nil(T, k))))))))))

# a line at the limit is cut hard: the block cannot be open beside it, and
# the line's text is a piece of exactly cap code points with no line feed
def hard_ok(
  +T: String,
  +cap: Nat,
  -c0: Nat,
  hcap: {cap == 1n+c0 : Nat},
  E: Nat,
  +E2: Nat,
  b: P.Block,
  +off: U32,
  +c: Char,
  +t: String,
  +out: List<&2, P.Para>,
  +lsuf: String,
  +lstart: U32,
  +llen: Nat,
  +k: Nat,
  +kl: Nat,
  +A: String,
  +eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == SCon{c, t} : String},
  +en: {Nat.add(k, 1n+String.length(t)) == String.length(T) : Nat},
  +ec: {D1.nl(c) == False{} : Bool},
  el: {lstart == U32.from_nat(kl) : U32},
  eds: {String.drop(T, kl) == lsuf : String},
  +ek: {k == Nat.add(llen, kl) : Nat},
  +er: {Nat.add(llen, 0n) == cap : Nat},
  ea: {lsuf == A ++ SCon{c, t} : String},
  +ela: {String.length(A) == llen : Nat},
  +enl: {D1.nonl(A) == True{} : Bool},
  a: M3.all(T, cap, out),
  tl: M2.tile(T, E, out, E2),
  bi: M2.binv(T, cap, E2, b, kl, 1n+llen)
) -> stepgood(T, cap, E, t, P.Para.grow.cut(cap, off, c, t,
  List.append(&2, P.Para, out,
    P.Para.flush(b, P.Para.emit(lsuf, lstart, off, llen, Nil{}))))):
  match b:
    case P.Open{_psuf, _pstart, _pend, plen, room}:
      match bi:
        case (_kp, (_B, (_es, (_edp, (_ee, (_ekl, (erm, _z))))))):
          Empty.absurd(stepgood(T, cap, E, t, P.Para.grow.cut(cap, off, c, t,
              List.append(&2, P.Para, out,
                P.Para.flush(P.Open{_psuf, _pstart, _pend, plen, room},
                  P.Para.emit(lsuf, lstart, off, llen, Nil{}))))),
            no_grow(plen, llen, room,
              Equal.trans(Nat, Nat.add(plen, 1n+Nat.add(llen, room)), cap, llen, erm,
                Equal.trans(Nat, cap, Nat.add(llen, 0n), llen,
                  Equal.sym(Nat, Nat.add(llen, 0n), cap, er), M2.add_zero_r(llen)))))
    case P.Shut{}:
      cut_ok(T, cap, c0, hcap, E, E2, off, c, t, out,
        P.Para.emit(lsuf, lstart, off, llen, Nil{}), k, eo, ed, en, ec, a, tl,
        M4.put(T, cap, E2, lsuf, lstart, off, llen, Nil{}, k, kl, A, el, eds,
          Equal.trans(U32, off, U32.from_nat(k), U32.from_nat(Nat.add(llen, kl)), eo,
            Equal.cong(Nat, U32, x => U32.from_nat(x), k, Nat.add(llen, kl), ek)),
          1n+String.length(t),
          (%ek : {Nat.add(_, 1n+String.length(t)) == String.length(T) : Nat}; en),
          0n, er,
          Equal.trans(String, lsuf, A ++ SCon{c, t},
            A ++ String.drop(T, Nat.add(llen, kl)), ea,
            Equal.cong(String, String, z => A ++ z, SCon{c, t},
              String.drop(T, Nat.add(llen, kl)),
              Equal.sym(String, String.drop(T, Nat.add(llen, kl)), SCon{c, t},
                (%ek : {String.drop(T, _) == SCon{c, t} : String}; ed)))),
          ela,
          Inr{Inr{(Equal.trans(Nat, String.length(A), llen, cap, ela,
            Equal.trans(Nat, llen, Nat.add(llen, 0n), cap,
              Equal.sym(Nat, Nat.add(llen, 0n), llen, M2.add_zero_r(llen)), er)), enl)}},
          nonl_full(A, enl), bi, Unit{}, (%ek : M1.gap(T, _, k); gap_nil(T, k))))

# a code point that is no line feed joins the line, cutting it at the limit
def gl_ok(
  +T: String,
  +cap: Nat,
  -c0: Nat,
  hcap: {cap == 1n+c0 : Nat},
  E: Nat,
  +off: U32,
  +c: Char,
  +t: String,
  e: P.Ended,
  ln: P.Line,
  +k: Nat,
  +kl: Nat,
  +eo: {off == U32.from_nat(k) : U32},
  +ed: {String.drop(T, k) == SCon{c, t} : String},
  +en: {Nat.add(k, 1n+String.length(t)) == String.length(T) : Nat},
  +ec: {D1.nl(c) == False{} : Bool},
  lf: M2.lfacts(T, cap, k, kl, SCon{c, t}, ln),
  ge: growgood(T, cap, E, kl, M2.lenof(ln), e)
) -> stepgood(T, cap, E, t, P.Para.grow.line(cap, off, c, t, e, ln)):
  match e ln:
    case P.Ended{+out, +b} P.Line{+lsuf, +lstart, +llen, lroom, +flag}:
      match lroom:
        case 1n+r:
          match lf:
            case (+A, (el, (eds, (ek, (er, (ea, (+ela, (+enl, eim)))))))):
              match ge:
                case (a, z):
                  match z:
                    case (+E2, w):
                      match w:
                        case (tl, bi):
                          (a, (E2, (tl, (1n+k, (kl,
                            (Equal.cong(U32, U32, x => U32.inc(x), off, U32.from_nat(k), eo),
                            (M2.drop_step(T, k, c, t, ed), (en_step(T, k, t, en),
                            ((A ++ SCon{c, SNil{}}, (el, (eds,
                              (Equal.cong(Nat, Nat, x => 1n+x, k, Nat.add(llen, kl), ek),
                              (Equal.trans(Nat, 1n+Nat.add(llen, r), Nat.add(llen, 1n+r),
                                cap, Equal.sym(Nat, Nat.add(llen, 1n+r),
                                  1n+Nat.add(llen, r), M2.add_succ_r(llen, r)), er),
                              (Equal.trans(String, lsuf, A ++ SCon{c, t},
                                (A ++ SCon{c, SNil{}}) ++ t, ea,
                                Equal.sym(String, (A ++ SCon{c, SNil{}}) ++ t,
                                  A ++ SCon{c, t}, M4.app_assoc(A, SCon{c, SNil{}}, t))),
                              (Equal.trans(Nat, String.length(A ++ SCon{c, SNil{}}),
                                Nat.add(String.length(A), 1n), 1n+llen,
                                M4.len_app(A, SCon{c, SNil{}}),
                                Equal.trans(Nat, Nat.add(String.length(A), 1n),
                                  Nat.add(llen, 1n), 1n+llen,
                                  Equal.cong(Nat, Nat, x => Nat.add(x, 1n),
                                    String.length(A), llen, ela),
                                  Equal.trans(Nat, Nat.add(llen, 1n), 1n+Nat.add(llen, 0n),
                                    1n+llen, M2.add_succ_r(llen, 0n),
                                    Equal.cong(Nat, Nat, x => 1n+x, Nat.add(llen, 0n),
                                      llen, M2.add_zero_r(llen))))),
                              (nonl_app(A, SCon{c, SNil{}}, enl, nonl_one(c, ec)),
                                blank_grow(A, c, flag, eim))))))))),
                            bi)))))))))
        case 0n:
          match lf:
            case (+A, (el, (eds, (ek, (er, (ea, (ela, (enl, _eim)))))))):
              match ge:
                case (a, z):
                  match z:
                    case (+E2, w):
                      match w:
                        case (tl, bi):
                          hard_ok(T, cap, c0, hcap, E, E2, b, off, c, t, out, lsuf,
                            lstart, llen, k, kl, A, eo, ed, en, ec, el, eds, ek, er, ea,
                            ela, enl, a, tl, bi)

# one code point keeps the invariant, line feed or not
def step_if_ok(
  nl: Bool,
  +T: String,
  +cap: Nat,
  -c0: Nat,
  hcap: {cap == 1n+c0 : Nat},
  +E: Nat,
  +c: Char,
  +t: String,
  st: P.Scan,
  inv0: M2.inv(T, cap, E, SCon{c, t}, st),
  +enl: {P.Para.is_nl(c) == nl : Bool}
) -> stepgood(T, cap, E, t, P.Para.step.if(nl, cap, c, t, st)):
  match nl:
    case True{}:
      match st:
        case P.Scan{+off, +b, +ln}:
          match inv0:
            case (+k, (+kl, (+eo, (+ed, (+en, (lf, bi)))))):
              nl_ok(T, cap, E, off, c, t, P.Para.close(off, b, ln), k, eo, ed, en, enl,
                close_ok(T, cap, E, SCon{c, t}, off, b, ln, k, kl, eo, ed, lf, bi,
                  Inr{(c, (t, ({==}, enl)))}))
    case False{}:
      match st:
        case P.Scan{+off, +b, ln}:
          match ln:
            case P.Line{+lsuf, +lstart, +llen, +lroom, +flag}:
              match inv0:
                case (+k, (+kl, (+eo, (+ed, (+en, (lf, bi)))))):
                  match lf:
                    case (+A, (+el, (+eds, (+ek, (+er, (+ea, (+ela, (+enl2, eim)))))))):
                      gl_ok(T, cap, c0, hcap, E, off, c, t, P.Para.grow.block(b),
                        P.Line{lsuf, lstart, llen, lroom, flag}, k, kl, eo, ed, en, enl,
                        (A, (el, (eds, (ek, (er, (ea, (ela, (enl2, eim)))))))),
                        gb_ok(T, cap, E, b, kl, llen, lsuf, A, c, t, eds, ea, ela, enl2,
                          enl, bi))

# one code point keeps the invariant
def step_ok(
  +T: String,
  +cap: Nat,
  -c0: Nat,
  hcap: {cap == 1n+c0 : Nat},
  +E: Nat,
  +c: Char,
  +t: String,
  st: P.Scan,
  inv0: M2.inv(T, cap, E, SCon{c, t}, st)
) -> stepgood(T, cap, E, t, P.Para.step(cap, c, t, st)):
  step_if_ok(P.Para.is_nl(c), T, cap, c0, hcap, E, c, t, st, inv0, {==})

# good paragraphs tiled from E to M, then good paragraphs tiled from M on
def combine(
  -T: String,
  -cap: Nat,
  +E: Nat,
  -M: Nat,
  +out: List<&2, P.Para>,
  ys: List<&2, P.Para>,
  a: M3.all(T, cap, out),
  tl: M2.tile(T, E, out, M),
  r: Pair(M3.all(T, cap, ys), M2.tile(T, M, ys, String.length(T)))
) -> Pair(M3.all(T, cap, List.append(&2, P.Para, out, ys)),
  M2.tile(T, E, List.append(&2, P.Para, out, ys), String.length(T))):
  match r:
    case (a2, t2):
      (all_append(T, cap, out, ys, a, a2),
        tile_app(out, T, E, M, ys, String.length(T), tl, t2))

# the scan of what is left after t gives good paragraphs that tile T, from
# every state keeping the invariant
def rest_ok(T: String, cap: Nat, t: String, k: P.Scan -> List<&2, P.Para>) -> Type:
  @E2: Nat -> @s2: P.Scan -> M2.inv(T, cap, E2, t, s2)
    -> Pair(M3.all(T, cap, k(s2)), M2.tile(T, E2, k(s2), String.length(T)))

# a step's paragraphs, then the paragraphs of the rest
def then_ok(
  -T: String,
  -cap: Nat,
  +E: Nat,
  -t: String,
  s: P.Step,
  k: P.Scan -> List<&2, P.Para>,
  hs: stepgood(T, cap, E, t, s),
  hk: rest_ok(T, cap, t, k)
) -> Pair(M3.all(T, cap, P.Para.then(s, k)), M2.tile(T, E, P.Para.then(s, k), String.length(T))):
  match s:
    case P.Step{out, +next}:
      match hs:
        case (a, z):
          match z:
            case (+E2, w):
              match w:
                case (tl, i):
                  combine(T, cap, E, E2, out, k(next), a, tl, hk(E2, next, i))

# a run ending at the end of T
def end_nil(-T: String, -m: Nat, +edr: {String.drop(T, m) == SNil{} : String}) -> M3.endl(T, m):
  Inl{((%Equal.sym(String, String.drop(T, m), SNil{}, edr)
      : {D1.blank(_) == True{} : Bool}; {==}), Inl{edr})}

# the block at the end of the text: flushed, it ends there
def fin_blk(
  +T: String,
  +cap: Nat,
  +E2: Nat,
  b: P.Block,
  -k: Nat,
  +ekN: {k == String.length(T) : Nat},
  bc: bclosed(T, cap, E2, b, k, SNil{})
) -> Pair(M3.all(T, cap, P.Para.flush(b, Nil{})),
  M2.tile(T, E2, P.Para.flush(b, Nil{}), String.length(T))):
  match b:
    case P.Shut{}:
      (Unit{}, (%ekN : M1.gap(T, E2, _); bc))
    case P.Open{psuf, pstart, pend, +plen, room}:
      match bc:
        case (+kp, (+B, (es, (edp, (ee, (+ekm, (erm, (eb, (elb, ((gE, (nb1, nb2)), edr)))))))))):
          M4.put(T, cap, E2, psuf, pstart, pend, plen, Nil{}, String.length(T), kp, B,
            es, edp, ee, 0n,
            Equal.trans(Nat, Nat.add(Nat.add(plen, kp), 0n), Nat.add(plen, kp),
              String.length(T), M2.add_zero_r(Nat.add(plen, kp)),
              Equal.trans(Nat, Nat.add(plen, kp), k, String.length(T),
                Equal.sym(Nat, k, Nat.add(plen, kp), ekm), ekN)),
            room, erm, eb, elb,
            Inl{end_nil(T, Nat.add(plen, kp), edr)},
            blk_full(B, nb1, nb2), gE, Unit{},
            (%Equal.sym(Nat, Nat.add(plen, kp), String.length(T),
                Equal.trans(Nat, Nat.add(plen, kp), k, String.length(T),
                  Equal.sym(Nat, k, Nat.add(plen, kp), ekm), ekN))
              : M1.gap(T, _, String.length(T));
              gap_nil(T, String.length(T))))

# the end of the text: the last line ends, and the block is flushed
def finish_ok(
  +T: String,
  +cap: Nat,
  +E: Nat,
  e: P.Ended,
  -k: Nat,
  ekN: {k == String.length(T) : Nat},
  he: endgood(T, cap, E, k, SNil{}, e)
) -> Pair(M3.all(T, cap, P.Para.finish(e)), M2.tile(T, E, P.Para.finish(e), String.length(T))):
  match e:
    case P.Ended{+out, +b}:
      match he:
        case (a, z):
          match z:
            case (+E2, w):
              match w:
                case (tl, bc):
                  combine(T, cap, E, E2, out, P.Para.flush(b, Nil{}), a, tl,
                    fin_blk(T, cap, E2, b, k, ekN, bc))

# every paragraph the scan emits from a state keeping the invariant is
# good, and they tile T from E to its end
def go_ok(
  rest: String,
  +T: String,
  +cap: Nat,
  +c0: Nat,
  +hcap: {cap == 1n+c0 : Nat},
  +E: Nat,
  +st: P.Scan,
  inv0: M2.inv(T, cap, E, rest, st)
) -> Pair(M3.all(T, cap, P.Para.go(rest, cap, st)),
  M2.tile(T, E, P.Para.go(rest, cap, st), String.length(T))):
  match rest:
    case SNil{}:
      match st:
        case P.Scan{+off, +b, +ln}:
          match inv0:
            case (+k, (+kl, (+eo, (+ed, (en, (lf, bi)))))):
              finish_ok(T, cap, E, P.Para.close(off, b, ln), k,
                Equal.trans(Nat, k, Nat.add(k, 0n), String.length(T),
                  Equal.sym(Nat, Nat.add(k, 0n), k, M2.add_zero_r(k)), en),
                close_ok(T, cap, E, SNil{}, off, b, ln, k, kl, eo, ed, lf, bi, Inl{{==}}))
    case SCon{+c, +t}:
      then_ok(T, cap, E, t, P.Para.step(cap, c, t, st), s => P.Para.go(t, cap, s),
        step_ok(T, cap, c0, hcap, E, c, t, st, inv0),
        E2 => s2 => h => go_ok(t, T, cap, c0, hcap, E2, s2, h))

# --- the paragraphs of a text ---

# the scan's first state keeps the invariant
def init_ok(
  +T: String,
  -cap: Nat
) -> M2.inv(T, cap, 0n, T, P.Scan{0, P.Shut{}, P.Line{T, 0, 0n, cap, True{}}}):
  (0n, (0n, ({==}, (M2.drop_zero(T), ({==},
    ((SNil{}, ({==}, (M2.drop_zero(T), ({==}, ({==}, ({==}, ({==}, ({==}, {==})))))))),
      gap_nil(T, 0n)))))))

# numbering keeps what the scan gives
def num_ok(
  -T: String,
  -cap: Nat,
  +xs: List<&2, P.Para>,
  r: Pair(M3.all(T, cap, xs), M2.tile(T, 0n, xs, String.length(T)))
) -> Pair(M3.all(T, cap, P.Para.number(xs, 1)),
  M2.tile(T, 0n, P.Para.number(xs, 1), String.length(T))):
  match r:
    case (a, t):
      (all_number(T, cap, xs, 1, a), tile_number(xs, T, 0n, String.length(T), 1, t))

# every paragraph of Para.split(T) is good, and they tile T
def splitres(T: String) -> Type:
  Pair(M3.all(T, U32.to_nat(P.Para.max()), P.Para.split(T)),
    M2.tile(T, 0n, P.Para.split(T), String.length(T)))

# splitres holds of every text
def split_ok(+T: String) -> splitres(T):
  +cap = U32.to_nat(P.Para.max())
  num_ok(T, cap, P.Para.go(T, cap, P.Scan{0, P.Shut{}, P.Line{T, 0, 0n, cap, True{}}}),
    go_ok(T, T, cap, 3999n, {==}, 0n,
      P.Scan{0, P.Shut{}, P.Line{T, 0, 0n, cap, True{}}}, init_ok(T, cap)))

# the good half
def split_all(
  -T: String,
  r: splitres(T)
) -> M3.all(T, U32.to_nat(P.Para.max()), P.Para.split(T)):
  match r:
    case (a, _t):
      a

# a paragraph of Para.split(T) is good
def good_split(
  +T: String,
  -p: P.Para,
  h: D1.In(p, P.Para.split(T))
) -> M3.good(T, U32.to_nat(P.Para.max()), p):
  in_good(T, U32.to_nat(P.Para.max()), p, P.Para.split(T), h,
    split_all(T, split_ok(T)))

# --- the laws ---

# a paragraph's end inside T survives the round trip when T's length does
def rt_end(
  -T: String,
  +l: Nat,
  +k: Nat,
  +q: Nat,
  eq: {Nat.add(Nat.add(l, k), q) == String.length(T) : Nat},
  fits: M2.rt(String.length(T))
) -> M2.rt(Nat.add(l, k)):
  M2.rt_add(Nat.add(l, k), q,
    M2.rt_cast(String.length(T), Nat.add(Nat.add(l, k), q),
      Equal.sym(Nat, Nat.add(Nat.add(l, k), q), String.length(T), eq), fits))

# the slice from k to l + k is the text, once both ends survive the round
# trip through U32
def offsets_fin(
  -T: String,
  +l: Nat,
  +k: Nat,
  -s: U32,
  -e: U32,
  -t: String,
  es: {s == U32.from_nat(k) : U32},
  ee: {e == U32.from_nat(Nat.add(l, k)) : U32},
  et: {String.take(String.drop(T, k), l) == t : String},
  +rte: {U32.to_nat(U32.from_nat(Nat.add(l, k))) == Nat.add(l, k) : Nat}
) -> {D1.slice(T, U32.to_nat(s), U32.to_nat(e)) == t : String}:
  %Equal.sym(U32, s, U32.from_nat(k), es)
    : {D1.slice(T, U32.to_nat(_), U32.to_nat(e)) == t : String}
  %Equal.sym(U32, e, U32.from_nat(Nat.add(l, k)), ee)
    : {D1.slice(T, U32.to_nat(U32.from_nat(k)), U32.to_nat(_)) == t : String}
  %Equal.sym(Nat, U32.to_nat(U32.from_nat(k)), k,
      M2.rt_add(k, l, M2.rt_cast(Nat.add(l, k), Nat.add(k, l), M2.add_comm(l, k), rte)))
    : {D1.slice(T, _, U32.to_nat(U32.from_nat(Nat.add(l, k)))) == t : String}
  %Equal.sym(Nat, U32.to_nat(U32.from_nat(Nat.add(l, k))), Nat.add(l, k), rte)
    : {D1.slice(T, k, _) == t : String}
  %Equal.sym(Nat, Nat.sub(Nat.add(l, k), k), l, sub_add(l, k))
    : {String.take(String.drop(T, k), _) == t : String}
  et
