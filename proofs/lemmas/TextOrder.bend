# comparing bits, words and texts, and source directory names
import Base
import ../../src/shard.bend as S
import ../../laws/SourceDirsAreSafeAndDistinct.bend as L1
import ../../laws/defs/Specification.bend as D1
import ./BoolFacts.bend as M1

# --- the line feed is whitespace ---

# Unit for EQ, Empty for any other
def iseq(c: Cmp) -> Type:
  match c:
    case EQ{}:
      Unit
    case _o:
      Empty

# a compare whose is_eq is True answered EQ
def cmp_eq(c: Cmp, e: {Cmp.is_eq(c) == True{} : Bool}) -> {c == EQ{} : Cmp}:
  match c:
    case LT{}:
      Empty.absurd({LT{} == EQ{} : Cmp}, M1.clash(e))
    case EQ{}:
      {==}
    case GT{}:
      Empty.absurd({GT{} == EQ{} : Cmp}, M1.clash(e))

# two bits that compare EQ are one
def bit_eq(a: Bool, b: Bool, e: {Bool.cmp(a, b) == EQ{} : Cmp}) -> {a == b : Bool}:
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      Empty.absurd({False{} == True{} : Bool},
        (%Equal.sym(Cmp, LT{}, EQ{}, e) : iseq(_); Unit{}))
    case True{} False{}:
      Empty.absurd({True{} == False{} : Bool},
        (%Equal.sym(Cmp, GT{}, EQ{}, e) : iseq(_); Unit{}))
    case True{} True{}:
      {==}

# the top bits and the rest of two words that compare EQ are one, from what
# the rest compared
def word_eq.go(
  ab: Bool,
  bb: Bool,
  -p: Nat,
  -at: Word(p),
  -bt: Word(p),
  r: Cmp,
  er: {Word.cmp(p, at, bt) == r : Cmp},
  e: {Word.cmp.fin(ab, bb, r) == EQ{} : Cmp},
  ih: {Word.cmp(p, at, bt) == EQ{} : Cmp} -> {at == bt : Word(p)}
) -> {WCon{ab, at} == WCon{bb, bt} : Word(1n+p)}:
  match r:
    case LT{}:
      Empty.absurd({WCon{ab, at} == WCon{bb, bt} : Word(1n+p)},
        (%Equal.sym(Cmp, LT{}, EQ{}, e) : iseq(_); Unit{}))
    case GT{}:
      Empty.absurd({WCon{ab, at} == WCon{bb, bt} : Word(1n+p)},
        (%Equal.sym(Cmp, GT{}, EQ{}, e) : iseq(_); Unit{}))
    case EQ{}:
      %bit_eq(ab, bb, e) : {WCon{ab, at} == WCon{_, bt} : Word(1n+p)}
      Equal.cong(Word(p), Word(1n+p), w => WCon{ab, w}, at, bt, ih(er))

# two words that compare EQ are one
def word_eq(+n: Nat, a: Word(n), b: Word(n), e: {Word.cmp(n, a, b) == EQ{} : Cmp}) -> {a == b : Word(n)}:
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{ab, +at} WCon{bb, +bt}:
          word_eq.go(ab, bb, p, at, bt, Word.cmp(p, at, bt), {==}, e,
            x => word_eq(p, at, bt, x))

# two U32 that compare EQ are one
def u32_eq(a: U32, b: U32, e: {U32.cmp(a, b) == EQ{} : Cmp}) -> {a == b : U32}:
  match a b:
    case U32{x} U32{y}:
      Equal.cong(Word(32n), U32, w => U32{w}, x, y, word_eq(32n, x, y, e))

# --- sources: order facts ---

# a comparison seen from the other side
def cflip(c: Cmp) -> Cmp:
  match c:
    case LT{}:
      GT{}
    case EQ{}:
      EQ{}
    case GT{}:
      LT{}

# two bits compared the other way round give the flipped answer
def bool_cmp_flip(a: Bool, b: Bool) -> {Bool.cmp(b, a) == cflip(Bool.cmp(a, b)) : Cmp}:
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

# the last step of a word comparison, flipped
def fin_flip(
  +ab: Bool,
  +bb: Bool,
  t: Cmp
) -> {Word.cmp.fin(bb, ab, cflip(t)) == cflip(Word.cmp.fin(ab, bb, t)) : Cmp}:
  match t:
    case LT{}:
      {==}
    case EQ{}:
      bool_cmp_flip(ab, bb)
    case GT{}:
      {==}

# two words compared the other way round give the flipped answer
def word_cmp_flip(
  n: Nat,
  +a: Word(n),
  +b: Word(n)
) -> {Word.cmp(n, b, a) == cflip(Word.cmp(n, a, b)) : Cmp}:
  match n:
    case 0n:
      {==}
    case 1n+(+p):
      match a b:
        case WCon{+ab, +at} WCon{+bb, +bt}:
          %Equal.sym(Cmp, Word.cmp(p, bt, at), cflip(Word.cmp(p, at, bt)),
            word_cmp_flip(p, at, bt))
            : {Word.cmp.fin(bb, ab, _) == cflip(Word.cmp.fin(ab, bb,
              Word.cmp(p, at, bt))) : Cmp}
          fin_flip(ab, bb, Word.cmp(p, at, bt))

# two numbers compared the other way round give the flipped answer
def u32_cmp_flip(+x: U32, +y: U32) -> {U32.cmp(y, x) == cflip(U32.cmp(x, y)) : Cmp}:
  match x y:
    case U32{+a} U32{+b}:
      word_cmp_flip(32n, a, b)

# two texts compared the other way round give the flipped answer
law order_flip:
  for +a: String
  for +b: String
  for +c: Cmp
  {String.order.go(b, a, cflip(c)) == cflip(String.order.go(a, b, c)) : Cmp}

def order_flip(a, b, c):
  match a b:
    case SNil{} SNil{}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}
    case SNil{} SCon{Chr{+y}, +t2}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}
    case SCon{Chr{+x}, +t1} SNil{}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}
    case SCon{Chr{+x}, +t1} SCon{Chr{+y}, +t2}:
      match c:
        case LT{}:
          {==}
        case EQ{}:
          %Equal.sym(Cmp, U32.cmp(y, x), cflip(U32.cmp(x, y)),
            u32_cmp_flip(x, y))
            : {String.order.go(t2, t1, _)
              == cflip(String.order.go(t1, t2, U32.cmp(x, y))) : Cmp}
          order_flip(t1, t2, U32.cmp(x, y))
        case GT{}:
          {==}

# a text comparison that ends equal started equal
law order_eq_c:
  for +a: String
  for +b: String
  for +c: Cmp
  for e: {Cmp.is_eq(String.order.go(a, b, c)) == True{} : Bool}
  {Cmp.is_eq(c) == True{} : Bool}

def order_eq_c(a, b, c, e):
  match a b:
    case SNil{} SNil{}:
      e
    case SNil{} SCon{Chr{+y}, +t2}:
      match c:
        case LT{}:
          e
        case EQ{}:
          {==}
        case GT{}:
          e
    case SCon{Chr{+x}, +t1} SNil{}:
      match c:
        case LT{}:
          e
        case EQ{}:
          {==}
        case GT{}:
          e
    case SCon{Chr{+x}, +t1} SCon{Chr{+y}, +t2}:
      match c:
        case LT{}:
          e
        case EQ{}:
          {==}
        case GT{}:
          e

# texts whose comparison ends equal are equal
law order_eq:
  for +a: String
  for +b: String
  for +c: Cmp
  for +e: {Cmp.is_eq(String.order.go(a, b, c)) == True{} : Bool}
  {a == b : String}

def order_eq(a, b, c, e):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{+y}, +t2}:
      match c:
        case LT{}:
          Empty.absurd({SNil{} == SCon{Chr{y}, t2} : String}, M1.clash(e))
        case EQ{}:
          Empty.absurd({SNil{} == SCon{Chr{y}, t2} : String}, M1.clash(e))
        case GT{}:
          Empty.absurd({SNil{} == SCon{Chr{y}, t2} : String}, M1.clash(e))
    case SCon{Chr{+x}, +t1} SNil{}:
      match c:
        case LT{}:
          Empty.absurd({SCon{Chr{x}, t1} == SNil{} : String}, M1.clash(e))
        case EQ{}:
          Empty.absurd({SCon{Chr{x}, t1} == SNil{} : String}, M1.clash(e))
        case GT{}:
          Empty.absurd({SCon{Chr{x}, t1} == SNil{} : String}, M1.clash(e))
    case SCon{Chr{+x}, +t1} SCon{Chr{+y}, +t2}:
      match c:
        case LT{}:
          Empty.absurd({SCon{Chr{x}, t1} == SCon{Chr{y}, t2} : String}, M1.clash(e))
        case EQ{}:
          %u32_eq(x, y, cmp_eq(U32.cmp(x, y), order_eq_c(t1, t2, U32.cmp(x, y), e)))
            : {SCon{Chr{x}, t1} == SCon{Chr{_}, t2} : String}
          Equal.cong(String, String, s => SCon{Chr{x}, s}, t1, t2,
            order_eq(t1, t2, U32.cmp(x, y), e))
        case GT{}:
          Empty.absurd({SCon{Chr{x}, t1} == SCon{Chr{y}, t2} : String}, M1.clash(e))

# texts String.order calls equal are equal
def str_eq(+a: String, +b: String, e: {String.order(a, b) == EQ{} : Cmp}) -> {a == b : String}:
  order_eq(a, b, EQ{},
    Equal.cong(Cmp, Bool, c => Cmp.is_eq(c), String.order(a, b), EQ{}, e))

# --- sources: membership ---

# or with its left side again
def or_dup(b: Bool, -m: Bool) -> {Bool.or(b, m) == Bool.or(b, Bool.or(b, m)) : Bool}:
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

# or's left sides swapped
def or_swap(
  a: Bool,
  b: Bool,
  -m: Bool
) -> {Bool.or(a, Bool.or(b, m)) == Bool.or(b, Bool.or(a, m)) : Bool}:
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

# membership after a put at y, by how a compared to y
def mem_insert.at(
  c: Cmp,
  +x: String,
  +a: String,
  +y: String,
  +rest: List<&2, String>,
  +ins: List<&2, String>,
  e: {String.order(a, y) == c : Cmp},
  ih: {D1.mem(x, ins) == Bool.or(String.eq(x, a), D1.mem(x, rest)) : Bool}
) -> {D1.mem(x, S.Shard.insert.at(c, a, y, rest, ins))
  == Bool.or(String.eq(x, a), D1.mem(x, y <> rest)) : Bool}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      %Equal.sym(String, a, y, str_eq(a, y, e))
        : {Bool.or(String.eq(x, y), D1.mem(x, rest))
          == Bool.or(String.eq(x, _), Bool.or(String.eq(x, y), D1.mem(x, rest)))
          : Bool}
      or_dup(String.eq(x, y), D1.mem(x, rest))
    case GT{}:
      %Equal.sym(Bool, D1.mem(x, ins),
        Bool.or(String.eq(x, a), D1.mem(x, rest)), ih)
        : {Bool.or(String.eq(x, y), _)
          == Bool.or(String.eq(x, a), Bool.or(String.eq(x, y), D1.mem(x, rest)))
          : Bool}
      or_swap(String.eq(x, y), String.eq(x, a), D1.mem(x, rest))

# a text is a member after a put exactly when it is the one put or was one
law mem_insert:
  for +ys: List<&2, String>
  for +x: String
  for +a: String
  {D1.mem(x, S.Shard.insert(ys, a))
    == Bool.or(String.eq(x, a), D1.mem(x, ys)) : Bool}

def mem_insert(ys, x, a):
  match ys:
    case Nil{}:
      {==}
    case Con{+y, +rest}:
      mem_insert.at(String.order(a, y), x, a, y, rest, S.Shard.insert(rest, a),
        {==}, mem_insert(rest, x, a))

# a code point the one-code-point text k is equal to is k's code point
def chr_eq(c: Char, +k: Char, e: {S.Shard.is(c, SCon{k, SNil{}}) == True{} : Bool}) -> {c == k : Char}:
  Equal.cong(String, Char, s => M1.hd(s, c), SCon{c, SNil{}}, SCon{k, SNil{}},
    order_eq(SCon{c, SNil{}}, SCon{k, SNil{}}, EQ{}, e))

# a code point's directory name reads back as it, ahead of the rest's
def round_ch(
  p: Bool,
  sl: Bool,
  d: Bool,
  +c: Char,
  +r: String,
  -rest: String,
  ep: {S.Shard.is(c, "%") == p : Bool},
  es: {S.Shard.is(c, "/") == sl : Bool},
  ed: {S.Shard.is(c, ".") == d : Bool},
  ih: {S.Shard.undir.go(r, S.Plain{}) == Some{rest} : Maybe<&2, String>}
) -> {S.Shard.undir.go(S.Shard.dir.ch(p, sl, d, c, r), S.Plain{}) == Some{SCon{c, rest}}
  : Maybe<&2, String>}:
  match p sl d:
    case True{} _ _:
      %Equal.sym(Maybe<&2, String>, S.Shard.undir.go(r, S.Plain{}), Some{rest}, ih)
        : {S.Shard.undir.cons(Some{'%'}, _) == Some{SCon{c, rest}} : Maybe<&2, String>}
      %Equal.sym(Char, c, '%', chr_eq(c, '%', ep))
        : {Some{SCon{'%', rest}} == Some{SCon{_, rest}} : Maybe<&2, String>}
      {==}
    case False{} True{} _:
      %Equal.sym(Maybe<&2, String>, S.Shard.undir.go(r, S.Plain{}), Some{rest}, ih)
        : {S.Shard.undir.cons(Some{'/'}, _) == Some{SCon{c, rest}} : Maybe<&2, String>}
      %Equal.sym(Char, c, '/', chr_eq(c, '/', es))
        : {Some{SCon{'/', rest}} == Some{SCon{_, rest}} : Maybe<&2, String>}
      {==}
    case False{} False{} True{}:
      %Equal.sym(Maybe<&2, String>, S.Shard.undir.go(r, S.Plain{}), Some{rest}, ih)
        : {S.Shard.undir.cons(Some{'.'}, _) == Some{SCon{c, rest}} : Maybe<&2, String>}
      %Equal.sym(Char, c, '.', chr_eq(c, '.', ed))
        : {Some{SCon{'.', rest}} == Some{SCon{_, rest}} : Maybe<&2, String>}
      {==}
    case False{} False{} False{}:
      %Equal.sym(Bool, S.Shard.is(c, "%"), False{}, ep)
        : {S.Shard.undir.plain(_, Bool.or(S.Shard.is(c, "/"), S.Shard.is(c, ".")), c,
            S.Shard.undir.go(r, Bool.pick(S.Pend, _, S.Pct{}, S.Plain{})))
          == Some{SCon{c, rest}} : Maybe<&2, String>}
      %Equal.sym(Bool, S.Shard.is(c, "/"), False{}, es)
        : {S.Shard.undir.plain(False{}, Bool.or(_, S.Shard.is(c, ".")), c,
            S.Shard.undir.go(r, S.Plain{}))
          == Some{SCon{c, rest}} : Maybe<&2, String>}
      %Equal.sym(Bool, S.Shard.is(c, "."), False{}, ed)
        : {S.Shard.undir.plain(False{}, Bool.or(False{}, _), c,
            S.Shard.undir.go(r, S.Plain{}))
          == Some{SCon{c, rest}} : Maybe<&2, String>}
      %Equal.sym(Maybe<&2, String>, S.Shard.undir.go(r, S.Plain{}), Some{rest}, ih)
        : {S.Shard.undir.cons(Some{c}, _) == Some{SCon{c, rest}} : Maybe<&2, String>}
      {==}

# laws/SourceDirsAreSafeAndDistinct.bend: a directory name reads back as its source
def L1.dir_round(src):
  match src:
    case SNil{}:
      {==}
    case SCon{+c, +rest}:
      round_ch(S.Shard.is(c, "%"), S.Shard.is(c, "/"), S.Shard.is(c, "."), c,
        S.Shard.dir(rest), rest, {==}, {==}, {==}, L1.dir_round(rest))
