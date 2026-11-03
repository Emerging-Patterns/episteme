# proofs of laws/MergeOrdersByTime.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/excerpt.bend as E
import ../laws/MergeOrdersByTime.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ../laws/defs/Specification.bend as D2
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/ExcerptIds.bend as M2
import ./lemmas/NatArithmetic.bend as M3
import ./lemmas/OffsetsHeld.bend as M4
import ./lemmas/PackingSteps.bend as M5
import ./lemmas/TakeAndAppend.bend as M6
import ./lemmas/TextOrder.bend as M7

# an is_le that is False answered GT
def le_gt(c: Cmp, e: {Cmp.is_le(c) == False{} : Bool}) -> {c == GT{} : Cmp}:
  match c:
    case LT{}:
      Empty.absurd({LT{} == GT{} : Cmp}, M1.clash(Equal.sym(Bool, True{}, False{}, e)))
    case EQ{}:
      Empty.absurd({EQ{} == GT{} : Cmp}, M1.clash(Equal.sym(Bool, True{}, False{}, e)))
    case GT{}:
      {==}

# a text not at most another is above it, so the other is at most it
def le_flip(
  +a: String,
  +b: String,
  e: {String.is_le(a, b) == False{} : Bool}
) -> {String.is_le(b, a) == True{} : Bool}:
  %Equal.sym(Cmp, String.order.go(b, a, EQ{}),
    M7.cflip(String.order.go(a, b, EQ{})), M7.order_flip(a, b, EQ{}))
    : {Cmp.is_le(_) == True{} : Bool}
  %Equal.sym(Cmp, String.order(a, b), GT{}, le_gt(String.order(a, b), e))
    : {Cmp.is_le(M7.cflip(_)) == True{} : Bool}
  {==}

# what slot_rising_from says of x slotted into rest, above y
def rise_ih(x: E.Ex, y: E.Ex, rest: List<&2, E.Ex>) -> Type:
  {String.is_le(D2.ex.ts(y), D2.ex.ts(x)) == True{} : Bool}
    -> {Laws.rising.from(rest, D2.ex.ts(y)) == True{} : Bool}
    -> {Laws.rising.from(E.Excerpt.slot(x, rest), D2.ex.ts(y)) == True{} : Bool}

# a slot above prev keeps rising, at y by how x compared to it
def slot_rising_from.at(
  +x: E.Ex,
  +y: E.Ex,
  +rest: List<&2, E.Ex>,
  +prev: String,
  b: Bool,
  eb: {String.is_le(D2.ex.ts(x), D2.ex.ts(y)) == b : Bool},
  e1: {String.is_le(prev, D2.ex.ts(x)) == True{} : Bool},
  +e2: {Laws.rising.from(y <> rest, prev) == True{} : Bool},
  ih: rise_ih(x, y, rest)
) -> {Laws.rising.from(E.Excerpt.slot.if(b, x, y, rest, _u => E.Excerpt.slot(x, rest)),
  prev) == True{} : Bool}:
  match b:
    case True{}:
      M6.and_tt(String.is_le(prev, D2.ex.ts(x)),
        Laws.rising.from(y <> rest, D2.ex.ts(x)), e1,
        M6.and_tt(String.is_le(D2.ex.ts(x), D2.ex.ts(y)),
          Laws.rising.from(rest, D2.ex.ts(y)), eb,
          M1.and_r(String.is_le(prev, D2.ex.ts(y)),
            Laws.rising.from(rest, D2.ex.ts(y)), e2)))
    case False{}:
      M6.and_tt(String.is_le(prev, D2.ex.ts(y)),
        Laws.rising.from(E.Excerpt.slot(x, rest), D2.ex.ts(y)),
        M1.and_l(String.is_le(prev, D2.ex.ts(y)),
          Laws.rising.from(rest, D2.ex.ts(y)), e2),
        ih(le_flip(D2.ex.ts(x), D2.ex.ts(y), eb),
          M1.and_r(String.is_le(prev, D2.ex.ts(y)),
            Laws.rising.from(rest, D2.ex.ts(y)), e2)))

# x slotted into excerpts rising from prev, x not below prev, keeps them
# rising from prev
law slot_rising_from:
  for +x: E.Ex
  for ys: List<&2, E.Ex>
  for +prev: String
  for e1: {String.is_le(prev, D2.ex.ts(x)) == True{} : Bool}
  for e2: {Laws.rising.from(ys, prev) == True{} : Bool}
  {Laws.rising.from(E.Excerpt.slot(x, ys), prev) == True{} : Bool}

def slot_rising_from(x, ys, prev, e1, e2):
  match ys:
    case Nil{}:
      %Equal.sym(Bool, String.is_le(prev, D2.ex.ts(x)), True{}, e1)
        : {Bool.and(_, True{}) == True{} : Bool}
      {==}
    case Con{+y, +rest}:
      %Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(x)), D2.ex.ts(x), M6.ts_eq(x))
        : {Laws.rising.from(E.Excerpt.slot.if(String.is_le(_,
          E.Excerpt.ts(E.Excerpt.rec(y))), x, y, rest, _u => E.Excerpt.slot(x, rest)),
          prev) == True{} : Bool}
      %Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(y)), D2.ex.ts(y), M6.ts_eq(y))
        : {Laws.rising.from(E.Excerpt.slot.if(String.is_le(D2.ex.ts(x), _),
          x, y, rest, _u => E.Excerpt.slot(x, rest)), prev) == True{} : Bool}
      slot_rising_from.at(x, y, rest, prev,
        String.is_le(D2.ex.ts(x), D2.ex.ts(y)), {==}, e1, e2,
        h1 => h2 => slot_rising_from(x, rest, D2.ex.ts(y), h1, h2))

# a slot keeps rising excerpts rising, at y by how x compared to it
def slot_rising.at(
  +x: E.Ex,
  +y: E.Ex,
  +rest: List<&2, E.Ex>,
  b: Bool,
  eb: {String.is_le(D2.ex.ts(x), D2.ex.ts(y)) == b : Bool},
  e: {Laws.rising(y <> rest) == True{} : Bool}
) -> {Laws.rising(E.Excerpt.slot.if(b, x, y, rest, _u => E.Excerpt.slot(x, rest)))
  == True{} : Bool}:
  match b:
    case True{}:
      M6.and_tt(String.is_le(D2.ex.ts(x), D2.ex.ts(y)),
        Laws.rising.from(rest, D2.ex.ts(y)), eb, e)
    case False{}:
      slot_rising_from(x, rest, D2.ex.ts(y),
        le_flip(D2.ex.ts(x), D2.ex.ts(y), eb), e)

# x slotted into rising excerpts keeps them rising
law slot_rising:
  for +x: E.Ex
  for ys: List<&2, E.Ex>
  for e: {Laws.rising(ys) == True{} : Bool}
  {Laws.rising(E.Excerpt.slot(x, ys)) == True{} : Bool}

def slot_rising(x, ys, e):
  match ys:
    case Nil{}:
      {==}
    case Con{+y, +rest}:
      %Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(x)), D2.ex.ts(x), M6.ts_eq(x))
        : {Laws.rising(E.Excerpt.slot.if(String.is_le(_,
          E.Excerpt.ts(E.Excerpt.rec(y))), x, y, rest, _u => E.Excerpt.slot(x, rest)))
          == True{} : Bool}
      %Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(y)), D2.ex.ts(y), M6.ts_eq(y))
        : {Laws.rising(E.Excerpt.slot.if(String.is_le(D2.ex.ts(x), _),
          x, y, rest, _u => E.Excerpt.slot(x, rest))) == True{} : Bool}
      slot_rising.at(x, y, rest, String.is_le(D2.ex.ts(x), D2.ex.ts(y)),
        {==}, e)

# sorted excerpts are rising
law sort_rising:
  for ys: List<&2, E.Ex>
  {Laws.rising(E.Excerpt.sort(ys)) == True{} : Bool}

def sort_rising(ys):
  match ys:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      slot_rising(x, E.Excerpt.sort(rest), sort_rising(rest))

# texts String.eq calls equal are equal
def eq_same(+a: String, +b: String, e: {String.eq(a, b) == True{} : Bool}) -> {a == b : String}:
  M7.str_eq(a, b, M7.cmp_eq(String.order(a, b), e))

# when a is above b and a equals t, b does not equal t
def above_ne(
  +a: String,
  +b: String,
  +t: String,
  eg: {String.is_le(a, b) == False{} : Bool},
  ea: {String.eq(a, t) == True{} : Bool}
) -> {String.eq(b, t) == False{} : Bool}:
  %eq_same(a, t, ea) : {String.eq(b, _) == False{} : Bool}
  %Equal.sym(Cmp, String.order.go(b, a, EQ{}),
    M7.cflip(String.order.go(a, b, EQ{})), M7.order_flip(a, b, EQ{}))
    : {Cmp.is_eq(_) == False{} : Bool}
  %Equal.sym(Cmp, String.order(a, b), GT{}, le_gt(String.order(a, b), eg))
    : {Cmp.is_eq(M7.cflip(_)) == False{} : Bool}
  {==}

# two filter puts swap when they do not both keep
def put_swap(
  bx: Bool,
  by: Bool,
  -x: E.Ex,
  -y: E.Ex,
  -r: List<&2, E.Ex>,
  h: {bx == True{} : Bool} -> {by == False{} : Bool}
) -> {List.filter.put(E.Ex, y, List.filter.put(E.Ex, x, r, bx), by)
  == List.filter.put(E.Ex, x, List.filter.put(E.Ex, y, r, by), bx)
  : List<&2, E.Ex>}:
  match bx by:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      Empty.absurd({List.filter.put(E.Ex, y, List.filter.put(E.Ex, x, r, True{}),
        True{}) == List.filter.put(E.Ex, x, List.filter.put(E.Ex, y, r, True{}),
        True{}) : List<&2, E.Ex>}, M1.clash(Equal.sym(Bool, True{}, False{}, h({==}))))

# what slot_only says of x slotted into rest
def only_ih(t: String, x: E.Ex, rest: List<&2, E.Ex>) -> Type:
  {D2.only(t, E.Excerpt.slot(x, rest)) == List.filter.put(E.Ex, x,
    D2.only(t, rest), String.eq(D2.ex.ts(x), t)) : List<&2, E.Ex>}

# the excerpts of time t after a slot, at y by how x compared to it
def slot_only.at(
  +t: String,
  +x: E.Ex,
  +y: E.Ex,
  +rest: List<&2, E.Ex>,
  b: Bool,
  eb: {String.is_le(D2.ex.ts(x), D2.ex.ts(y)) == b : Bool},
  ih: only_ih(t, x, rest)
) -> {D2.only(t, E.Excerpt.slot.if(b, x, y, rest, _u => E.Excerpt.slot(x, rest)))
  == List.filter.put(E.Ex, x, D2.only(t, y <> rest),
    String.eq(D2.ex.ts(x), t)) : List<&2, E.Ex>}:
  match b:
    case True{}:
      {==}
    case False{}:
      %Equal.sym(List<&2, E.Ex>, D2.only(t, E.Excerpt.slot(x, rest)),
        List.filter.put(E.Ex, x, D2.only(t, rest), String.eq(D2.ex.ts(x), t)),
        ih)
        : {List.filter.put(E.Ex, y, _, String.eq(D2.ex.ts(y), t))
          == List.filter.put(E.Ex, x, D2.only(t, y <> rest),
          String.eq(D2.ex.ts(x), t)) : List<&2, E.Ex>}
      put_swap(String.eq(D2.ex.ts(x), t), String.eq(D2.ex.ts(y), t), x, y,
        D2.only(t, rest),
        ea => above_ne(D2.ex.ts(x), D2.ex.ts(y), t, eb, ea))

# the excerpts of time t after x is slotted are those before, with x where
# a stable sort puts it: after every earlier one of time t
law slot_only:
  for +t: String
  for +x: E.Ex
  for ys: List<&2, E.Ex>
  {D2.only(t, E.Excerpt.slot(x, ys)) == List.filter.put(E.Ex, x,
    D2.only(t, ys), String.eq(D2.ex.ts(x), t)) : List<&2, E.Ex>}

def slot_only(t, x, ys):
  match ys:
    case Nil{}:
      {==}
    case Con{+y, +rest}:
      %Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(x)), D2.ex.ts(x), M6.ts_eq(x))
        : {D2.only(t, E.Excerpt.slot.if(String.is_le(_,
          E.Excerpt.ts(E.Excerpt.rec(y))), x, y, rest, _u => E.Excerpt.slot(x, rest)))
          == List.filter.put(E.Ex, x, D2.only(t, y <> rest),
          String.eq(D2.ex.ts(x), t)) : List<&2, E.Ex>}
      %Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(y)), D2.ex.ts(y), M6.ts_eq(y))
        : {D2.only(t, E.Excerpt.slot.if(String.is_le(D2.ex.ts(x), _),
          x, y, rest, _u => E.Excerpt.slot(x, rest)))
          == List.filter.put(E.Ex, x, D2.only(t, y <> rest),
          String.eq(D2.ex.ts(x), t)) : List<&2, E.Ex>}
      slot_only.at(t, x, y, rest, String.is_le(D2.ex.ts(x), D2.ex.ts(y)),
        {==}, slot_only(t, x, rest))

# sorting keeps the excerpts of each time in order
law sort_only:
  for +t: String
  for ys: List<&2, E.Ex>
  {D2.only(t, E.Excerpt.sort(ys)) == D2.only(t, ys) : List<&2, E.Ex>}

def sort_only(t, ys):
  match ys:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(List<&2, E.Ex>, D2.only(t, E.Excerpt.slot(x, E.Excerpt.sort(rest))),
        List.filter.put(E.Ex, x, D2.only(t, E.Excerpt.sort(rest)),
          String.eq(D2.ex.ts(x), t)),
        slot_only(t, x, E.Excerpt.sort(rest)))
        : {_ == List.filter.put(E.Ex, x, D2.only(t, rest),
          String.eq(D2.ex.ts(x), t)) : List<&2, E.Ex>}
      Equal.cong(List<&2, E.Ex>, List<&2, E.Ex>,
        z => List.filter.put(E.Ex, x, z, String.eq(D2.ex.ts(x), t)),
        D2.only(t, E.Excerpt.sort(rest)), D2.only(t, rest), sort_only(t, rest))

# the code's firsts, either way by whether seen
def firsts_at(
  b: Bool,
  +x: E.Ex,
  -a: List<&2, E.Ex>,
  -c: List<&2, E.Ex>,
  e: {a == c : List<&2, E.Ex>}
) -> {E.Excerpt.firsts.if(b, x, a) == Laws.first.if(b, x, c) : List<&2, E.Ex>}:
  match b:
    case True{}:
      e
    case False{}:
      Equal.cong(List<&2, E.Ex>, List<&2, E.Ex>, z => x <> z, a, c, e)

# the code's first excerpt of each record is the specification's
law firsts_eq:
  for xs: List<&2, E.Ex>
  for +seen: List<&2, String>
  {E.Excerpt.firsts(xs, seen) == Laws.firsts(xs, seen) : List<&2, E.Ex>}

def firsts_eq(xs, seen):
  match xs:
    case Nil{}:
      {==}
    case Con{x, +rest}:
      match x:
        case E.Ex{rec, +ps}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +rps, +ptr}:
              +xx = {E.Ex{R.Record{id, ts, source, author, thread, parent, rps,
                ptr}, ps} : E.Ex}
              %Equal.sym(Bool, E.Excerpt.named(id, seen), D2.mem(id, seen),
                M4.named_mem(id, seen))
                : {E.Excerpt.firsts.if(_, xx, E.Excerpt.firsts(rest, id <> seen))
                  == Laws.first.if(D2.mem(id, seen), xx,
                    Laws.firsts(rest, id <> seen)) : List<&2, E.Ex>}
              firsts_at(D2.mem(id, seen), xx, E.Excerpt.firsts(rest, id <> seen),
                Laws.firsts(rest, id <> seen), firsts_eq(rest, id <> seen))

# or regrouped
def or_assoc(
  a: Bool,
  -b: Bool,
  -c: Bool
) -> {Bool.or(a, Bool.or(b, c)) == Bool.or(Bool.or(a, b), c) : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# the excerpts after a slot hold what they held and x, at y by how x
# compared to it
def holds_slot.at(
  +id: String,
  +n: U32,
  +x: E.Ex,
  +y: E.Ex,
  +rest: List<&2, E.Ex>,
  b: Bool,
  ih: {D2.holds(id, n, E.Excerpt.slot(x, rest)) == D2.holds(id, n, x <> rest) : Bool}
) -> {D2.holds(id, n, E.Excerpt.slot.if(b, x, y, rest, _u => E.Excerpt.slot(x, rest)))
  == D2.holds(id, n, x <> y <> rest) : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      %Equal.sym(Bool, D2.holds(id, n, E.Excerpt.slot(x, rest)),
        D2.holds(id, n, x <> rest), ih)
        : {Bool.or(Bool.and(String.eq(D2.rec.id(D2.ex.rec(y)), id),
          D2.numbered(n, D2.ex.paras(y))), _)
          == D2.holds(id, n, x <> y <> rest) : Bool}
      M7.or_swap(Bool.and(String.eq(D2.rec.id(D2.ex.rec(y)), id),
          D2.numbered(n, D2.ex.paras(y))),
        Bool.and(String.eq(D2.rec.id(D2.ex.rec(x)), id),
          D2.numbered(n, D2.ex.paras(x))), D2.holds(id, n, rest))

# slotting x in holds what putting it ahead holds
law holds_slot:
  for +id: String
  for +n: U32
  for +x: E.Ex
  for ys: List<&2, E.Ex>
  {D2.holds(id, n, E.Excerpt.slot(x, ys)) == D2.holds(id, n, x <> ys) : Bool}

def holds_slot(id, n, x, ys):
  match ys:
    case Nil{}:
      {==}
    case Con{+y, +rest}:
      holds_slot.at(id, n, x, y, rest,
        String.is_le(E.Excerpt.ts(E.Excerpt.rec(x)), E.Excerpt.ts(E.Excerpt.rec(y))),
        holds_slot(id, n, x, rest))

# sorting holds what it sorted
law holds_sort:
  for +id: String
  for +n: U32
  for ys: List<&2, E.Ex>
  {D2.holds(id, n, E.Excerpt.sort(ys)) == D2.holds(id, n, ys) : Bool}

def holds_sort(id, n, ys):
  match ys:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(Bool, D2.holds(id, n, E.Excerpt.slot(x, E.Excerpt.sort(rest))),
        D2.holds(id, n, x <> E.Excerpt.sort(rest)),
        holds_slot(id, n, x, E.Excerpt.sort(rest)))
        : {_ == D2.holds(id, n, x <> rest) : Bool}
      Equal.cong(Bool, Bool,
        z => Bool.or(Bool.and(String.eq(D2.rec.id(D2.ex.rec(x)), id),
          D2.numbered(n, D2.ex.paras(x))), z),
        D2.holds(id, n, E.Excerpt.sort(rest)), D2.holds(id, n, rest),
        holds_sort(id, n, rest))

# what numbered_place says of p placed among rest
def numbered_ih(n: U32, p: P.Para, rest: List<&2, P.Para>) -> Type:
  {D2.numbered(n, E.Excerpt.place(p, rest))
    == Bool.or(U32.is_eq(D2.para.n(p), n), D2.numbered(n, rest)) : Bool}

# a place, at q by how p's number compared to q's
def numbered_place.at(
  +n: U32,
  +p: P.Para,
  +q: P.Para,
  +rest: List<&2, P.Para>,
  c: Cmp,
  ec: {U32.cmp(D2.para.n(p), D2.para.n(q)) == c : Cmp},
  ih: numbered_ih(n, p, rest)
) -> {D2.numbered(n, E.Excerpt.place.at(c, p, q, rest, E.Excerpt.place(p, rest)))
  == Bool.or(U32.is_eq(D2.para.n(p), n), D2.numbered(n, q <> rest)) : Bool}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      %M7.u32_eq(D2.para.n(p), D2.para.n(q), ec)
        : {Bool.or(U32.is_eq(D2.para.n(p), n), D2.numbered(n, rest))
          == Bool.or(U32.is_eq(D2.para.n(p), n),
          Bool.or(U32.is_eq(_, n), D2.numbered(n, rest))) : Bool}
      M7.or_dup(U32.is_eq(D2.para.n(p), n), D2.numbered(n, rest))
    case GT{}:
      %Equal.sym(Bool, D2.numbered(n, E.Excerpt.place(p, rest)),
        Bool.or(U32.is_eq(D2.para.n(p), n), D2.numbered(n, rest)), ih)
        : {Bool.or(U32.is_eq(D2.para.n(q), n), _)
          == Bool.or(U32.is_eq(D2.para.n(p), n), D2.numbered(n, q <> rest))
          : Bool}
      M7.or_swap(U32.is_eq(D2.para.n(q), n), U32.is_eq(D2.para.n(p), n),
        D2.numbered(n, rest))

# placing p adds its number and drops none
law numbered_place:
  for +n: U32
  for +p: P.Para
  for zs: List<&2, P.Para>
  {D2.numbered(n, E.Excerpt.place(p, zs))
    == Bool.or(U32.is_eq(D2.para.n(p), n), D2.numbered(n, zs)) : Bool}

def numbered_place(n, p, zs):
  match p:
    case P.Para{+pn, +ps, +pe, +pt}:
      match zs:
        case Nil{}:
          {==}
        case Con{q, +rest}:
          match q:
            case P.Para{+qn, +qs, +qe, +qt}:
              numbered_place.at(n, P.Para{pn, ps, pe, pt}, P.Para{qn, qs, qe, qt},
                rest, U32.cmp(pn, qn), {==},
                numbered_place(n, P.Para{pn, ps, pe, pt}, rest))

# the numbers of a union are those of both
law numbered_union:
  for +n: U32
  for ps: List<&2, P.Para>
  for +qs: List<&2, P.Para>
  {D2.numbered(n, E.Excerpt.union(ps, qs))
    == Bool.or(D2.numbered(n, ps), D2.numbered(n, qs)) : Bool}

def numbered_union(n, ps, qs):
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +rest}:
      %Equal.sym(Bool, D2.numbered(n, E.Excerpt.place(p, E.Excerpt.union(rest, qs))),
        Bool.or(U32.is_eq(D2.para.n(p), n),
          D2.numbered(n, E.Excerpt.union(rest, qs))),
        numbered_place(n, p, E.Excerpt.union(rest, qs)))
        : {_ == Bool.or(D2.numbered(n, p <> rest), D2.numbered(n, qs)) : Bool}
      %Equal.sym(Bool, D2.numbered(n, E.Excerpt.union(rest, qs)),
        Bool.or(D2.numbered(n, rest), D2.numbered(n, qs)),
        numbered_union(n, rest, qs))
        : {Bool.or(U32.is_eq(D2.para.n(p), n), _)
          == Bool.or(D2.numbered(n, p <> rest), D2.numbered(n, qs)) : Bool}
      or_assoc(U32.is_eq(D2.para.n(p), n), D2.numbered(n, rest),
        D2.numbered(n, qs))

# gathering a record's paragraphs or not, either way by the numbers
def gather_at(
  b: Bool,
  +n: U32,
  +ps: List<&2, P.Para>,
  +g: List<&2, P.Para>,
  -h: Bool,
  ih: {D2.numbered(n, g) == h : Bool}
) -> {D2.numbered(n, E.Excerpt.gather.if(b, ps, g))
  == Bool.or(Bool.and(b, D2.numbered(n, ps)), h) : Bool}:
  match b:
    case True{}:
      %Equal.sym(Bool, D2.numbered(n, E.Excerpt.union(ps, g)),
        Bool.or(D2.numbered(n, ps), D2.numbered(n, g)),
        numbered_union(n, ps, g))
        : {_ == Bool.or(D2.numbered(n, ps), h) : Bool}
      Equal.cong(Bool, Bool, z => Bool.or(D2.numbered(n, ps), z),
        D2.numbered(n, g), h, ih)
    case False{}:
      ih

# a number is among the paragraphs gathered for a record exactly when an
# excerpt of that record holds it
law numbered_gather:
  for +n: U32
  for +i: String
  for xs: List<&2, E.Ex>
  {D2.numbered(n, E.Excerpt.gather(i, xs)) == D2.holds(i, n, xs) : Bool}

def numbered_gather(n, i, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{x, +rest}:
      match x:
        case E.Ex{rec, +ps}:
          match rec:
            case R.Record{+id, _ts, _source, _author, _thread, _parent, _rps, _ptr}:
              gather_at(String.eq(id, i), n, ps, E.Excerpt.gather(i, rest),
                D2.holds(i, n, rest), numbered_gather(n, i, rest))

# h or (s and h) is h
def absorb(h: Bool, s: Bool) -> {Bool.or(h, Bool.and(s, h)) == h : Bool}:
  match h:
    case True{}:
      {==}
    case False{}:
      M3.and_false(s)

# a joined excerpt holds n for id when its record is id's and some input
# excerpt of id holds n
def holds_join.at(
  a: Bool,
  +rid: String,
  +id: String,
  +n: U32,
  +all: List<&2, E.Ex>,
  s: Bool,
  ea: {String.eq(rid, id) == a : Bool}
) -> {Bool.or(Bool.and(a, D2.holds(rid, n, all)),
  Bool.and(s, D2.holds(id, n, all)))
  == Bool.and(Bool.or(a, s), D2.holds(id, n, all)) : Bool}:
  match a:
    case True{}:
      %Equal.sym(String, rid, id, eq_same(rid, id, ea))
        : {Bool.or(D2.holds(_, n, all), Bool.and(s, D2.holds(id, n, all)))
          == D2.holds(id, n, all) : Bool}
      absorb(D2.holds(id, n, all), s)
    case False{}:
      {==}

# what the joined excerpts hold: n for id when one of them is id's and
# some input excerpt of id holds n
law holds_join:
  for +id: String
  for +n: U32
  for fs: List<&2, E.Ex>
  for +all: List<&2, E.Ex>
  {D2.holds(id, n, E.Excerpt.join(fs, all))
    == Bool.and(M2.ids(id, fs), D2.holds(id, n, all)) : Bool}

def holds_join(id, n, fs, all):
  match fs:
    case Nil{}:
      {==}
    case Con{f, +rest}:
      match f:
        case E.Ex{rec, _ps}:
          match rec:
            case R.Record{+rid, _ts, _source, _author, _thread, _parent, _rps, _ptr}:
              %Equal.sym(Bool, D2.numbered(n, E.Excerpt.gather(rid, all)),
                D2.holds(rid, n, all), numbered_gather(n, rid, all))
                : {Bool.or(Bool.and(String.eq(rid, id), _),
                  D2.holds(id, n, E.Excerpt.join(rest, all)))
                  == Bool.and(Bool.or(String.eq(rid, id), M2.ids(id, rest)),
                    D2.holds(id, n, all)) : Bool}
              %Equal.sym(Bool, D2.holds(id, n, E.Excerpt.join(rest, all)),
                Bool.and(M2.ids(id, rest), D2.holds(id, n, all)),
                holds_join(id, n, rest, all))
                : {Bool.or(Bool.and(String.eq(rid, id), D2.holds(rid, n, all)), _)
                  == Bool.and(Bool.or(String.eq(rid, id), M2.ids(id, rest)),
                    D2.holds(id, n, all)) : Bool}
              holds_join.at(String.eq(rid, id), rid, id, n, all, M2.ids(id, rest), {==})

# an excerpt holding n for id has the record id id
def holds_ids.at(
  a: Bool,
  -nn: Bool,
  -s: Bool,
  -h: Bool,
  ih: {Bool.and(s, h) == h : Bool}
) -> {Bool.and(Bool.or(a, s), Bool.or(Bool.and(a, nn), h))
  == Bool.or(Bool.and(a, nn), h) : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      ih

# whatever holds n for id has id among its record ids
law holds_ids:
  for +id: String
  for +n: U32
  for xs: List<&2, E.Ex>
  {Bool.and(M2.ids(id, xs), D2.holds(id, n, xs)) == D2.holds(id, n, xs) : Bool}

def holds_ids(id, n, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      holds_ids.at(String.eq(D2.rec.id(D2.ex.rec(x)), id),
        D2.numbered(n, D2.ex.paras(x)), M2.ids(id, rest), D2.holds(id, n, rest),
        holds_ids(id, n, rest))

# Cmp.is_eq is blind to which side is which
def is_eq_flip(c: Cmp) -> {Cmp.is_eq(c) == Cmp.is_eq(M7.cflip(c)) : Bool}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      {==}

# String.eq is symmetric
def eq_sym(+a: String, +b: String) -> {String.eq(a, b) == String.eq(b, a) : Bool}:
  %Equal.sym(Cmp, String.order.go(b, a, EQ{}),
    M7.cflip(String.order.go(a, b, EQ{})), M7.order_flip(a, b, EQ{}))
    : {Cmp.is_eq(String.order.go(a, b, EQ{})) == Cmp.is_eq(_) : Bool}
  is_eq_flip(String.order.go(a, b, EQ{}))

# move a Bool fact along an equation
def bcast(-T: Bool -> Type, -x: Bool, -y: Bool, e: {x == y : Bool}, h: T(x)) -> T(y):
  %e : T(_)
  h

# what ids_firsts says of the rest, seen grown by an id that is id when a
def idf_ih(a: Bool, id: String, seen: List<&2, String>, fl: List<&2, E.Ex>, rest: List<&2, E.Ex>) -> Type:
  {Bool.or(Bool.or(a, D2.mem(id, seen)), M2.ids(id, fl))
    == Bool.or(Bool.or(a, D2.mem(id, seen)), M2.ids(id, rest)) : Bool}

# the first excerpts, by whether x's id was seen and whether it is id
def idf_at(
  k: Bool,
  a: Bool,
  +id: String,
  +x: E.Ex,
  +seen: List<&2, String>,
  +fl: List<&2, E.Ex>,
  +rest: List<&2, E.Ex>,
  ek: {D2.mem(D2.rec.id(D2.ex.rec(x)), seen) == k : Bool},
  ea: {String.eq(D2.rec.id(D2.ex.rec(x)), id) == a : Bool},
  ih: idf_ih(a, id, seen, fl, rest)
) -> {Bool.or(D2.mem(id, seen), M2.ids(id, Laws.first.if(k, x, fl)))
  == Bool.or(D2.mem(id, seen),
    Bool.or(String.eq(D2.rec.id(D2.ex.rec(x)), id), M2.ids(id, rest))) : Bool}:
  match k a:
    case True{} True{}:
      +hm = {(%eq_same(D2.rec.id(D2.ex.rec(x)), id, ea)
        : {D2.mem(_, seen) == True{} : Bool}
        ek) : {D2.mem(id, seen) == True{} : Bool}}
      %Equal.sym(Bool, D2.mem(id, seen), True{}, hm)
        : {Bool.or(_, M2.ids(id, fl)) == Bool.or(_,
          Bool.or(String.eq(D2.rec.id(D2.ex.rec(x)), id), M2.ids(id, rest)))
          : Bool}
      {==}
    case True{} False{}:
      %Equal.sym(Bool, String.eq(D2.rec.id(D2.ex.rec(x)), id), False{}, ea)
        : {Bool.or(D2.mem(id, seen), M2.ids(id, fl))
          == Bool.or(D2.mem(id, seen), Bool.or(_, M2.ids(id, rest))) : Bool}
      ih
    case False{} True{}:
      %Equal.sym(Bool, String.eq(D2.rec.id(D2.ex.rec(x)), id), True{}, ea)
        : {Bool.or(D2.mem(id, seen), Bool.or(_, M2.ids(id, fl)))
          == Bool.or(D2.mem(id, seen), Bool.or(_, M2.ids(id, rest))) : Bool}
      {==}
    case False{} False{}:
      %Equal.sym(Bool, String.eq(D2.rec.id(D2.ex.rec(x)), id), False{}, ea)
        : {Bool.or(D2.mem(id, seen), Bool.or(_, M2.ids(id, fl)))
          == Bool.or(D2.mem(id, seen), Bool.or(_, M2.ids(id, rest))) : Bool}
      ih

# unless id was seen, the first excerpts have id exactly when the excerpts do
law ids_firsts:
  for +id: String
  for xs: List<&2, E.Ex>
  for +seen: List<&2, String>
  {Bool.or(D2.mem(id, seen), M2.ids(id, Laws.firsts(xs, seen)))
    == Bool.or(D2.mem(id, seen), M2.ids(id, xs)) : Bool}

def ids_firsts(id, xs, seen):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      +w = D2.rec.id(D2.ex.rec(x))
      idf_at(D2.mem(w, seen), String.eq(w, id), id, x, seen,
        Laws.firsts(rest, w <> seen), rest, {==}, {==},
        bcast(z => {Bool.or(Bool.or(z, D2.mem(id, seen)),
            M2.ids(id, Laws.firsts(rest, w <> seen)))
            == Bool.or(Bool.or(z, D2.mem(id, seen)), M2.ids(id, rest)) : Bool},
          String.eq(id, w), String.eq(w, id), eq_sym(id, w),
          ids_firsts(id, rest, w <> seen)))

# z after the first of a list is after it with another put second
def elem_skip(
  -z: E.Ex,
  -x: E.Ex,
  -y: E.Ex,
  -rest: List<&2, E.Ex>,
  h: D1.Elem(E.Ex, z, x <> rest)
) -> D1.Elem(E.Ex, z, x <> y <> rest):
  match h:
    case Inl{e}:
      Inl{e}
    case Inr{el}:
      Inr{Inr{el}}

# what is among excerpts after a slot was among them or is x, at y by how
# x compared to it
def elem_slot.at(
  b: Bool,
  -z: E.Ex,
  -x: E.Ex,
  -y: E.Ex,
  -rest: List<&2, E.Ex>,
  ih: D1.Elem(E.Ex, z, E.Excerpt.slot(x, rest)) -> D1.Elem(E.Ex, z, x <> rest),
  h: D1.Elem(E.Ex, z, E.Excerpt.slot.if(b, x, y, rest, _u => E.Excerpt.slot(x, rest)))
) -> D1.Elem(E.Ex, z, x <> y <> rest):
  match b:
    case True{}:
      h
    case False{}:
      match h:
        case Inl{e}:
          Inr{Inl{e}}
        case Inr{el}:
          elem_skip(z, x, y, rest, ih(el))

# what is among excerpts after x is slotted in is x or was among them
law elem_slot:
  for -z: E.Ex
  for +x: E.Ex
  for ys: List<&2, E.Ex>
  for h: D1.Elem(E.Ex, z, E.Excerpt.slot(x, ys))
  D1.Elem(E.Ex, z, x <> ys)

def elem_slot(z, x, ys, h):
  match ys:
    case Nil{}:
      h
    case Con{+y, +rest}:
      elem_slot.at(
        String.is_le(E.Excerpt.ts(E.Excerpt.rec(x)), E.Excerpt.ts(E.Excerpt.rec(y))),
        z, x, y, rest, hh => elem_slot(z, x, rest, hh), h)

# what is after x among a list moved along a map of the rest
def elem_tail(
  -z: E.Ex,
  -x: E.Ex,
  -a: List<&2, E.Ex>,
  -b: List<&2, E.Ex>,
  f: D1.Elem(E.Ex, z, a) -> D1.Elem(E.Ex, z, b),
  h: D1.Elem(E.Ex, z, x <> a)
) -> D1.Elem(E.Ex, z, x <> b):
  match h:
    case Inl{e}:
      Inl{e}
    case Inr{el}:
      Inr{f(el)}

# what is among sorted excerpts was among them
law elem_sort:
  for -z: E.Ex
  for ys: List<&2, E.Ex>
  for h: D1.Elem(E.Ex, z, E.Excerpt.sort(ys))
  D1.Elem(E.Ex, z, ys)

def elem_sort(z, ys, h):
  match ys:
    case Nil{}:
      h
    case Con{+x, +rest}:
      elem_tail(z, x, E.Excerpt.sort(rest), rest, hh => elem_sort(z, rest, hh),
        elem_slot(z, x, E.Excerpt.sort(rest), h))

# a joined excerpt's paragraphs are those gathered for its record id
law elem_join:
  for -z: E.Ex
  for fs: List<&2, E.Ex>
  for +all: List<&2, E.Ex>
  for h: D1.Elem(E.Ex, z, E.Excerpt.join(fs, all))
  {D2.ex.paras(z) == E.Excerpt.gather(D2.rec.id(D2.ex.rec(z)), all)
    : List<&2, P.Para>}

def elem_join(z, fs, all, h):
  match fs:
    case Nil{}:
      Empty.absurd({D2.ex.paras(z)
        == E.Excerpt.gather(D2.rec.id(D2.ex.rec(z)), all) : List<&2, P.Para>}, h)
    case Con{f, +rest}:
      match f:
        case E.Ex{rec, _ps}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +rps, +ptr}:
              match h:
                case Inl{e}:
                  %Equal.sym(E.Ex, z, E.Ex{R.Record{id, ts, source, author, thread,
                    parent, rps, ptr}, E.Excerpt.gather(id, all)}, e)
                    : {D2.ex.paras(_)
                      == E.Excerpt.gather(D2.rec.id(D2.ex.rec(_)), all)
                      : List<&2, P.Para>}
                  {==}
                case Inr{el}:
                  elem_join(z, rest, all, el)

# what place_from says of p placed among rest, above q
def climb_ih(p: P.Para, q: P.Para, rest: List<&2, P.Para>) -> Type:
  {U32.is_lt(D2.para.n(q), D2.para.n(p)) == True{} : Bool}
    -> {Laws.climbing.from(rest, D2.para.n(q)) == True{} : Bool}
    -> {Laws.climbing.from(E.Excerpt.place(p, rest), D2.para.n(q)) == True{} : Bool}

# a number below p's keeps a place climbing from prev, at q by how p's
# number compared to q's
def place_from.at(
  +p: P.Para,
  +q: P.Para,
  +rest: List<&2, P.Para>,
  +prev: U32,
  c: Cmp,
  ec: {U32.cmp(D2.para.n(p), D2.para.n(q)) == c : Cmp},
  e1: {U32.is_lt(prev, D2.para.n(p)) == True{} : Bool},
  +e2: {Laws.climbing.from(q <> rest, prev) == True{} : Bool},
  ih: climb_ih(p, q, rest)
) -> {Laws.climbing.from(E.Excerpt.place.at(c, p, q, rest, E.Excerpt.place(p, rest)),
  prev) == True{} : Bool}:
  match c:
    case LT{}:
      M6.and_tt(U32.is_lt(prev, D2.para.n(p)),
        Laws.climbing.from(q <> rest, D2.para.n(p)), e1,
        M6.and_tt(U32.is_lt(D2.para.n(p), D2.para.n(q)),
          Laws.climbing.from(rest, D2.para.n(q)),
          (%Equal.sym(Cmp, U32.cmp(D2.para.n(p), D2.para.n(q)), LT{}, ec)
            : {Cmp.is_lt(_) == True{} : Bool}
            {==}),
          M1.and_r(U32.is_lt(prev, D2.para.n(q)),
            Laws.climbing.from(rest, D2.para.n(q)), e2)))
    case EQ{}:
      %Equal.sym(U32, D2.para.n(p), D2.para.n(q),
        M7.u32_eq(D2.para.n(p), D2.para.n(q), ec))
        : {Bool.and(U32.is_lt(prev, _), Laws.climbing.from(rest, _)) == True{}
          : Bool}
      e2
    case GT{}:
      M6.and_tt(U32.is_lt(prev, D2.para.n(q)),
        Laws.climbing.from(E.Excerpt.place(p, rest), D2.para.n(q)),
        M1.and_l(U32.is_lt(prev, D2.para.n(q)),
          Laws.climbing.from(rest, D2.para.n(q)), e2),
        ih((%Equal.sym(Cmp, U32.cmp(D2.para.n(q), D2.para.n(p)),
            M7.cflip(U32.cmp(D2.para.n(p), D2.para.n(q))),
            M7.u32_cmp_flip(D2.para.n(p), D2.para.n(q)))
            : {Cmp.is_lt(_) == True{} : Bool}
          %Equal.sym(Cmp, U32.cmp(D2.para.n(p), D2.para.n(q)), GT{}, ec)
            : {Cmp.is_lt(M7.cflip(_)) == True{} : Bool}
          {==}),
          M1.and_r(U32.is_lt(prev, D2.para.n(q)),
            Laws.climbing.from(rest, D2.para.n(q)), e2)))

# p placed among paragraphs climbing from prev, p above prev, keeps them
# climbing from prev
law place_from:
  for +p: P.Para
  for zs: List<&2, P.Para>
  for +prev: U32
  for e1: {U32.is_lt(prev, D2.para.n(p)) == True{} : Bool}
  for e2: {Laws.climbing.from(zs, prev) == True{} : Bool}
  {Laws.climbing.from(E.Excerpt.place(p, zs), prev) == True{} : Bool}

def place_from(p, zs, prev, e1, e2):
  match p:
    case P.Para{+pn, +ps, +pe, +pt}:
      match zs:
        case Nil{}:
          %Equal.sym(Bool, U32.is_lt(prev, pn), True{}, e1)
            : {Bool.and(_, True{}) == True{} : Bool}
          {==}
        case Con{q, +rest}:
          match q:
            case P.Para{+qn, +qs, +qe, +qt}:
              place_from.at(P.Para{pn, ps, pe, pt}, P.Para{qn, qs, qe, qt}, rest,
                prev, U32.cmp(pn, qn), {==}, e1, e2,
                h1 => h2 => place_from(P.Para{pn, ps, pe, pt}, rest, qn, h1, h2))

# a place keeps climbing paragraphs climbing, at q by how p's number
# compared to q's
def place_climbing.at(
  +p: P.Para,
  +q: P.Para,
  +rest: List<&2, P.Para>,
  c: Cmp,
  ec: {U32.cmp(D2.para.n(p), D2.para.n(q)) == c : Cmp},
  e: {Laws.climbing(q <> rest) == True{} : Bool}
) -> {Laws.climbing(E.Excerpt.place.at(c, p, q, rest, E.Excerpt.place(p, rest)))
  == True{} : Bool}:
  match c:
    case LT{}:
      %Equal.sym(Cmp, U32.cmp(D2.para.n(p), D2.para.n(q)), LT{}, ec)
        : {Bool.and(Cmp.is_lt(_), Laws.climbing.from(rest, D2.para.n(q)))
          == True{} : Bool}
      e
    case EQ{}:
      %Equal.sym(U32, D2.para.n(p), D2.para.n(q),
        M7.u32_eq(D2.para.n(p), D2.para.n(q), ec))
        : {Laws.climbing.from(rest, _) == True{} : Bool}
      e
    case GT{}:
      place_from(p, rest, D2.para.n(q),
        (%Equal.sym(Cmp, U32.cmp(D2.para.n(q), D2.para.n(p)),
            M7.cflip(U32.cmp(D2.para.n(p), D2.para.n(q))),
            M7.u32_cmp_flip(D2.para.n(p), D2.para.n(q)))
            : {Cmp.is_lt(_) == True{} : Bool}
          %Equal.sym(Cmp, U32.cmp(D2.para.n(p), D2.para.n(q)), GT{}, ec)
            : {Cmp.is_lt(M7.cflip(_)) == True{} : Bool}
          {==}), e)

# p placed among climbing paragraphs keeps them climbing
law place_climbing:
  for +p: P.Para
  for zs: List<&2, P.Para>
  for e: {Laws.climbing(zs) == True{} : Bool}
  {Laws.climbing(E.Excerpt.place(p, zs)) == True{} : Bool}

def place_climbing(p, zs, e):
  match p:
    case P.Para{+pn, +ps, +pe, +pt}:
      match zs:
        case Nil{}:
          {==}
        case Con{q, +rest}:
          match q:
            case P.Para{+qn, +qs, +qe, +qt}:
              place_climbing.at(P.Para{pn, ps, pe, pt}, P.Para{qn, qs, qe, qt},
                rest, U32.cmp(pn, qn), {==}, e)

# a union with climbing paragraphs climbs
law union_climbing:
  for ps: List<&2, P.Para>
  for +qs: List<&2, P.Para>
  for e: {Laws.climbing(qs) == True{} : Bool}
  {Laws.climbing(E.Excerpt.union(ps, qs)) == True{} : Bool}

def union_climbing(ps, qs, e):
  match ps:
    case Nil{}:
      e
    case Con{+p, +rest}:
      place_climbing(p, E.Excerpt.union(rest, qs), union_climbing(rest, qs, e))

# a gather step keeps the gathered paragraphs climbing
def gather_climbing.at(
  b: Bool,
  +ps: List<&2, P.Para>,
  +g: List<&2, P.Para>,
  e: {Laws.climbing(g) == True{} : Bool}
) -> {Laws.climbing(E.Excerpt.gather.if(b, ps, g)) == True{} : Bool}:
  match b:
    case True{}:
      union_climbing(ps, g, e)
    case False{}:
      e

# the paragraphs gathered for a record climb
law gather_climbing:
  for +i: String
  for xs: List<&2, E.Ex>
  {Laws.climbing(E.Excerpt.gather(i, xs)) == True{} : Bool}

def gather_climbing(i, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      gather_climbing.at(String.eq(E.Excerpt.id(E.Excerpt.rec(x)), i),
        E.Excerpt.paras(x), E.Excerpt.gather(i, rest), gather_climbing(i, rest))

# p, or among rest, is p or among z and rest
def elem_place.gt(
  -q: P.Para,
  -p: P.Para,
  -z: P.Para,
  -rest: List<&2, P.Para>,
  o: Or({q == p : P.Para}, D1.Elem(P.Para, q, rest))
) -> Or({q == p : P.Para}, D1.Elem(P.Para, q, z <> rest)):
  match o:
    case Inl{e}:
      Inl{e}
    case Inr{el}:
      Inr{Inr{el}}

# what is among placed paragraphs is p or was among them, at z by how p's
# number compared to z's
def elem_place.at(
  c: Cmp,
  -q: P.Para,
  -p: P.Para,
  -z: P.Para,
  -rest: List<&2, P.Para>,
  ih: D1.Elem(P.Para, q, E.Excerpt.place(p, rest)) -> Or({q == p : P.Para}, D1.Elem(P.Para, q, rest)),
  h: D1.Elem(P.Para, q, E.Excerpt.place.at(c, p, z, rest, E.Excerpt.place(p, rest)))
) -> Or({q == p : P.Para}, D1.Elem(P.Para, q, z <> rest)):
  match c:
    case LT{}:
      h
    case EQ{}:
      match h:
        case Inl{e}:
          Inl{e}
        case Inr{el}:
          Inr{Inr{el}}
    case GT{}:
      match h:
        case Inl{e}:
          Inr{Inl{e}}
        case Inr{el}:
          elem_place.gt(q, p, z, rest, ih(el))

# what is among placed paragraphs is p or was among them
law elem_place:
  for -q: P.Para
  for +p: P.Para
  for zs: List<&2, P.Para>
  for h: D1.Elem(P.Para, q, E.Excerpt.place(p, zs))
  Or({q == p : P.Para}, D1.Elem(P.Para, q, zs))

def elem_place(q, p, zs, h):
  match zs:
    case Nil{}:
      h
    case Con{+z, +rest}:
      elem_place.at(U32.cmp(E.Excerpt.n(p), E.Excerpt.n(z)), q, p, z, rest,
        hh => elem_place(q, p, rest, hh), h)

# among rest or qs is among p and rest, or qs
def elem_union.step(
  -q: P.Para,
  -p: P.Para,
  -rest: List<&2, P.Para>,
  -qs: List<&2, P.Para>,
  o: Or(D1.Elem(P.Para, q, rest), D1.Elem(P.Para, q, qs))
) -> Or(D1.Elem(P.Para, q, p <> rest), D1.Elem(P.Para, q, qs)):
  match o:
    case Inl{a}:
      Inl{Inr{a}}
    case Inr{b}:
      Inr{b}

# p, or among the union of rest and qs, is among p and rest, or qs
def elem_union.at(
  -q: P.Para,
  -p: P.Para,
  -rest: List<&2, P.Para>,
  -qs: List<&2, P.Para>,
  f: D1.Elem(P.Para, q, E.Excerpt.union(rest, qs)) -> Or(D1.Elem(P.Para, q, rest), D1.Elem(P.Para, q, qs)),
  o: Or({q == p : P.Para}, D1.Elem(P.Para, q, E.Excerpt.union(rest, qs)))
) -> Or(D1.Elem(P.Para, q, p <> rest), D1.Elem(P.Para, q, qs)):
  match o:
    case Inl{e}:
      Inl{Inl{e}}
    case Inr{el}:
      elem_union.step(q, p, rest, qs, f(el))

# what is among a union was among one side
law elem_union:
  for -q: P.Para
  for ps: List<&2, P.Para>
  for +qs: List<&2, P.Para>
  for h: D1.Elem(P.Para, q, E.Excerpt.union(ps, qs))
  Or(D1.Elem(P.Para, q, ps), D1.Elem(P.Para, q, qs))

def elem_union(q, ps, qs, h):
  match ps:
    case Nil{}:
      Inr{h}
    case Con{+p, +rest}:
      elem_union.at(q, p, rest, qs, hh => elem_union(q, rest, qs, hh),
        elem_place(q, p, E.Excerpt.union(rest, qs), h))

# an excerpt among xs of record id i that holds q
def src_of(-q: P.Para, -i: String, xs: List<&2, E.Ex>) -> Type:
  Exists(E.Ex, y => Pair(D1.Elem(E.Ex, y, xs),
    Pair({D2.rec.id(D2.ex.rec(y)) == i : String},
      D1.Elem(P.Para, q, D2.ex.paras(y)))))

# an excerpt among rest is among x and rest
def src_lift(
  -q: P.Para,
  -i: String,
  -x: E.Ex,
  -rest: List<&2, E.Ex>,
  o: src_of(q, i, rest)
) -> src_of(q, i, x <> rest):
  match o:
    case (y, pr):
      match pr:
        case (el, r):
          (y, (Inr{el}, r))

# a gathered paragraph of x's, or of the rest, has its excerpt
def elem_gather.yes(
  -q: P.Para,
  +i: String,
  +xid: String,
  +x: E.Ex,
  -ps: List<&2, P.Para>,
  -g: List<&2, P.Para>,
  -rest: List<&2, E.Ex>,
  ex: {D2.rec.id(D2.ex.rec(x)) == xid : String},
  ep: {D2.ex.paras(x) == ps : List<&2, P.Para>},
  ei: {xid == i : String},
  ih: D1.Elem(P.Para, q, g) -> src_of(q, i, rest),
  o: Or(D1.Elem(P.Para, q, ps), D1.Elem(P.Para, q, g))
) -> src_of(q, i, x <> rest):
  match o:
    case Inl{a}:
      (x, (Inl{{==}}, (Equal.trans(String, D2.rec.id(D2.ex.rec(x)), xid, i,
        ex, ei), M4.elem_cast(P.Para, q, ps, D2.ex.paras(x),
        Equal.sym(List<&2, P.Para>, D2.ex.paras(x), ps, ep), a))))
    case Inr{b}:
      src_lift(q, i, x, rest, ih(b))

# a gathered paragraph of one excerpt or of the rest, by whether the
# excerpt is of record id i
def elem_gather.at(
  b: Bool,
  -q: P.Para,
  +i: String,
  +xid: String,
  +x: E.Ex,
  +ps: List<&2, P.Para>,
  +g: List<&2, P.Para>,
  -rest: List<&2, E.Ex>,
  ex: {D2.rec.id(D2.ex.rec(x)) == xid : String},
  ep: {D2.ex.paras(x) == ps : List<&2, P.Para>},
  eb: {String.eq(xid, i) == b : Bool},
  ih: D1.Elem(P.Para, q, g) -> src_of(q, i, rest),
  h: D1.Elem(P.Para, q, E.Excerpt.gather.if(b, ps, g))
) -> src_of(q, i, x <> rest):
  match b:
    case True{}:
      elem_gather.yes(q, i, xid, x, ps, g, rest, ex, ep, eq_same(xid, i, eb), ih,
        elem_union(q, ps, g, h))
    case False{}:
      src_lift(q, i, x, rest, ih(h))

# a paragraph gathered for record id i is a paragraph of an excerpt of i
law elem_gather:
  for -q: P.Para
  for +i: String
  for xs: List<&2, E.Ex>
  for h: D1.Elem(P.Para, q, E.Excerpt.gather(i, xs))
  src_of(q, i, xs)

def elem_gather(q, i, xs, h):
  match xs:
    case Nil{}:
      Empty.absurd(src_of(q, i, []), h)
    case Con{x, +rest}:
      match x:
        case E.Ex{rec, +ps}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +rps, +ptr}:
              +xx = {E.Ex{R.Record{id, ts, source, author, thread, parent, rps,
                ptr}, ps} : E.Ex}
              elem_gather.at(String.eq(id, i), q, i, id, xx, ps,
                E.Excerpt.gather(i, rest), rest, {==}, {==}, {==},
                hh => elem_gather(q, i, rest, hh), h)

# LT is not EQ
def lt_not_eq(e: {EQ{} == LT{} : Cmp}) -> Empty:
  M1.clash(Equal.cong(Cmp, Bool, c => Cmp.is_lt(c), EQ{}, LT{}, e))

# LT is not GT
def lt_not_gt(e: {GT{} == LT{} : Cmp}) -> Empty:
  M1.clash(Equal.cong(Cmp, Bool, c => Cmp.is_lt(c), GT{}, LT{}, e))

# a compare whose is_lt is True answered LT
def cmp_lt(c: Cmp, e: {Cmp.is_lt(c) == True{} : Bool}) -> {c == LT{} : Cmp}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      Empty.absurd({EQ{} == LT{} : Cmp}, M1.clash(e))
    case GT{}:
      Empty.absurd({GT{} == LT{} : Cmp}, M1.clash(e))

# the bit compares of a below b below c, all with equal rest, cannot both
# be LT
def bit_lt_trans(
  a: Bool,
  b: Bool,
  c: Bool,
  e1: {Bool.cmp(a, b) == LT{} : Cmp},
  e2: {Bool.cmp(b, c) == LT{} : Cmp}
) -> {Bool.cmp(a, c) == LT{} : Cmp}:
  match a b c:
    case False{} False{} False{}:
      Empty.absurd({EQ{} == LT{} : Cmp}, lt_not_eq(e1))
    case False{} False{} True{}:
      Empty.absurd({LT{} == LT{} : Cmp}, lt_not_eq(e1))
    case False{} True{} False{}:
      Empty.absurd({EQ{} == LT{} : Cmp}, lt_not_gt(e2))
    case False{} True{} True{}:
      Empty.absurd({LT{} == LT{} : Cmp}, lt_not_eq(e2))
    case True{} False{} False{}:
      Empty.absurd({GT{} == LT{} : Cmp}, lt_not_gt(e1))
    case True{} False{} True{}:
      Empty.absurd({EQ{} == LT{} : Cmp}, lt_not_gt(e1))
    case True{} True{} False{}:
      Empty.absurd({GT{} == LT{} : Cmp}, lt_not_eq(e1))
    case True{} True{} True{}:
      Empty.absurd({EQ{} == LT{} : Cmp}, lt_not_eq(e1))

# word compares, by how the rests compared
def word_lt_trans.at(
  ta: Cmp,
  tb: Cmp,
  +p: Nat,
  ab: Bool,
  bb: Bool,
  cb: Bool,
  +at: Word(p),
  +bt: Word(p),
  +ct: Word(p),
  ea: {Word.cmp(p, at, bt) == ta : Cmp},
  eb: {Word.cmp(p, bt, ct) == tb : Cmp},
  e1: {Word.cmp.fin(ab, bb, ta) == LT{} : Cmp},
  e2: {Word.cmp.fin(bb, cb, tb) == LT{} : Cmp},
  ih: {Word.cmp(p, at, bt) == LT{} : Cmp} -> {Word.cmp(p, bt, ct) == LT{} : Cmp} -> {Word.cmp(p, at, ct) == LT{} : Cmp}
) -> {Word.cmp.fin(ab, cb, Word.cmp(p, at, ct)) == LT{} : Cmp}:
  match ta tb:
    case LT{} LT{}:
      %Equal.sym(Cmp, Word.cmp(p, at, ct), LT{}, ih(ea, eb))
        : {Word.cmp.fin(ab, cb, _) == LT{} : Cmp}
      {==}
    case LT{} EQ{}:
      %M7.word_eq(p, bt, ct, eb)
        : {Word.cmp.fin(ab, cb, Word.cmp(p, at, _)) == LT{} : Cmp}
      %Equal.sym(Cmp, Word.cmp(p, at, bt), LT{}, ea)
        : {Word.cmp.fin(ab, cb, _) == LT{} : Cmp}
      {==}
    case EQ{} LT{}:
      %Equal.sym(Word(p), at, bt, M7.word_eq(p, at, bt, ea))
        : {Word.cmp.fin(ab, cb, Word.cmp(p, _, ct)) == LT{} : Cmp}
      %Equal.sym(Cmp, Word.cmp(p, bt, ct), LT{}, eb)
        : {Word.cmp.fin(ab, cb, _) == LT{} : Cmp}
      {==}
    case EQ{} EQ{}:
      %Equal.sym(Word(p), at, bt, M7.word_eq(p, at, bt, ea))
        : {Word.cmp.fin(ab, cb, Word.cmp(p, _, ct)) == LT{} : Cmp}
      %Equal.sym(Cmp, Word.cmp(p, bt, ct), EQ{}, eb)
        : {Word.cmp.fin(ab, cb, _) == LT{} : Cmp}
      bit_lt_trans(ab, bb, cb, e1, e2)
    case LT{} GT{}:
      Empty.absurd({Word.cmp.fin(ab, cb, Word.cmp(p, at, ct)) == LT{} : Cmp},
        lt_not_gt(e2))
    case EQ{} GT{}:
      Empty.absurd({Word.cmp.fin(ab, cb, Word.cmp(p, at, ct)) == LT{} : Cmp},
        lt_not_gt(e2))
    case GT{} _tb:
      Empty.absurd({Word.cmp.fin(ab, cb, Word.cmp(p, at, ct)) == LT{} : Cmp},
        lt_not_gt(e1))

# words below one another are below each other
law word_lt_trans:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Word(n)
  for e1: {Word.cmp(n, a, b) == LT{} : Cmp}
  for e2: {Word.cmp(n, b, c) == LT{} : Cmp}
  {Word.cmp(n, a, c) == LT{} : Cmp}

def word_lt_trans(n, a, b, c, e1, e2):
  match n:
    case 0n:
      Empty.absurd({Word.cmp(0n, a, c) == LT{} : Cmp}, lt_not_eq(e1))
    case 1n+(+p):
      match a b c:
        case WCon{ab, +at} WCon{bb, +bt} WCon{cb, +ct}:
          word_lt_trans.at(Word.cmp(p, at, bt), Word.cmp(p, bt, ct), p, ab, bb, cb,
            at, bt, ct, {==}, {==}, e1, e2,
            h1 => h2 => word_lt_trans(p, at, bt, ct, h1, h2))

# numbers below one another are below each other
def u32_lt_trans(
  x: U32,
  y: U32,
  z: U32,
  e1: {U32.cmp(x, y) == LT{} : Cmp},
  e2: {U32.cmp(y, z) == LT{} : Cmp}
) -> {U32.cmp(x, z) == LT{} : Cmp}:
  match x y z:
    case U32{+a} U32{+b} U32{+c}:
      word_lt_trans(32n, a, b, c, e1, e2)

# a text comparison begun LT stays LT
def go_lt(+a: String, +b: String) -> {String.order.go(a, b, LT{}) == LT{} : Cmp}:
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{_y}, _t2}:
      {==}
    case SCon{Chr{_x}, _t1} SNil{}:
      {==}
    case SCon{Chr{_x}, _t1} SCon{Chr{_y}, _t2}:
      {==}

# a text comparison begun GT stays GT
def go_gt(+a: String, +b: String) -> {String.order.go(a, b, GT{}) == GT{} : Cmp}:
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{Chr{_y}, _t2}:
      {==}
    case SCon{Chr{_x}, _t1} SNil{}:
      {==}
    case SCon{Chr{_x}, _t1} SCon{Chr{_y}, _t2}:
      {==}

# what str_lt_trans says of the rests
def str_ih(t1: String, t2: String, t3: String) -> Type:
  {String.order.go(t1, t2, EQ{}) == LT{} : Cmp}
    -> {String.order.go(t2, t3, EQ{}) == LT{} : Cmp}
    -> {String.order.go(t1, t3, EQ{}) == LT{} : Cmp}

# text compares past one code point, by how the code points compared
def str_lt_trans.at(
  cx: Cmp,
  cy: Cmp,
  +x: U32,
  +y: U32,
  +z: U32,
  +t1: String,
  +t2: String,
  +t3: String,
  ex: {U32.cmp(x, y) == cx : Cmp},
  ey: {U32.cmp(y, z) == cy : Cmp},
  e1: {String.order.go(t1, t2, cx) == LT{} : Cmp},
  e2: {String.order.go(t2, t3, cy) == LT{} : Cmp},
  ih: str_ih(t1, t2, t3)
) -> {String.order.go(t1, t3, U32.cmp(x, z)) == LT{} : Cmp}:
  match cx cy:
    case LT{} LT{}:
      %Equal.sym(Cmp, U32.cmp(x, z), LT{}, u32_lt_trans(x, y, z, ex, ey))
        : {String.order.go(t1, t3, _) == LT{} : Cmp}
      go_lt(t1, t3)
    case LT{} EQ{}:
      %M7.u32_eq(y, z, ey)
        : {String.order.go(t1, t3, U32.cmp(x, _)) == LT{} : Cmp}
      %Equal.sym(Cmp, U32.cmp(x, y), LT{}, ex)
        : {String.order.go(t1, t3, _) == LT{} : Cmp}
      go_lt(t1, t3)
    case EQ{} LT{}:
      %Equal.sym(U32, x, y, M7.u32_eq(x, y, ex))
        : {String.order.go(t1, t3, U32.cmp(_, z)) == LT{} : Cmp}
      %Equal.sym(Cmp, U32.cmp(y, z), LT{}, ey)
        : {String.order.go(t1, t3, _) == LT{} : Cmp}
      go_lt(t1, t3)
    case EQ{} EQ{}:
      %Equal.sym(U32, x, y, M7.u32_eq(x, y, ex))
        : {String.order.go(t1, t3, U32.cmp(_, z)) == LT{} : Cmp}
      %Equal.sym(Cmp, U32.cmp(y, z), EQ{}, ey)
        : {String.order.go(t1, t3, _) == LT{} : Cmp}
      ih(e1, e2)
    case LT{} GT{}:
      Empty.absurd({String.order.go(t1, t3, U32.cmp(x, z)) == LT{} : Cmp},
        lt_not_gt(Equal.trans(Cmp, GT{}, String.order.go(t2, t3, GT{}), LT{},
          Equal.sym(Cmp, String.order.go(t2, t3, GT{}), GT{}, go_gt(t2, t3)), e2)))
    case EQ{} GT{}:
      Empty.absurd({String.order.go(t1, t3, U32.cmp(x, z)) == LT{} : Cmp},
        lt_not_gt(Equal.trans(Cmp, GT{}, String.order.go(t2, t3, GT{}), LT{},
          Equal.sym(Cmp, String.order.go(t2, t3, GT{}), GT{}, go_gt(t2, t3)), e2)))
    case GT{} _cy:
      Empty.absurd({String.order.go(t1, t3, U32.cmp(x, z)) == LT{} : Cmp},
        lt_not_gt(Equal.trans(Cmp, GT{}, String.order.go(t1, t2, GT{}), LT{},
          Equal.sym(Cmp, String.order.go(t1, t2, GT{}), GT{}, go_gt(t1, t2)), e1)))

# texts below one another are below each other
law str_lt_trans:
  for +a: String
  for +b: String
  for +c: String
  for e1: {String.order.go(a, b, EQ{}) == LT{} : Cmp}
  for e2: {String.order.go(b, c, EQ{}) == LT{} : Cmp}
  {String.order.go(a, c, EQ{}) == LT{} : Cmp}

def str_lt_trans(a, b, c, e1, e2):
  match a b c:
    case SNil{} SNil{} _c:
      Empty.absurd({String.order.go(SNil{}, c, EQ{}) == LT{} : Cmp}, lt_not_eq(e1))
    case SNil{} SCon{Chr{_y}, _t2} SNil{}:
      Empty.absurd({String.order.go(SNil{}, SNil{}, EQ{}) == LT{} : Cmp},
        lt_not_gt(e2))
    case SNil{} SCon{Chr{_y}, _t2} SCon{Chr{_z}, _t3}:
      {==}
    case SCon{Chr{_x}, _t1} SNil{} _c:
      Empty.absurd({String.order.go(SCon{Chr{_x}, _t1}, c, EQ{}) == LT{} : Cmp},
        lt_not_gt(e1))
    case SCon{Chr{_x}, _t1} SCon{Chr{_y}, _t2} SNil{}:
      Empty.absurd({String.order.go(SCon{Chr{_x}, _t1}, SNil{}, EQ{}) == LT{} : Cmp},
        lt_not_gt(e2))
    case SCon{Chr{+x}, +t1} SCon{Chr{+y}, +t2} SCon{Chr{+z}, +t3}:
      str_lt_trans.at(U32.cmp(x, y), U32.cmp(y, z), x, y, z, t1, t2, t3, {==}, {==},
        e1, e2, h1 => h2 => str_lt_trans(t1, t2, t3, h1, h2))

# String.is_lt is transitive
def lt_trans(
  +a: String,
  +b: String,
  +c: String,
  e1: {String.is_lt(a, b) == True{} : Bool},
  e2: {String.is_lt(b, c) == True{} : Bool}
) -> {String.is_lt(a, c) == True{} : Bool}:
  %Equal.sym(Cmp, String.order(a, c), LT{},
    str_lt_trans(a, b, c, cmp_lt(String.order(a, b), e1),
      cmp_lt(String.order(b, c), e2)))
    : {Cmp.is_lt(_) == True{} : Bool}
  {==}

# a compare that is LT is at most
def lt_le(c: Cmp, e: {Cmp.is_lt(c) == True{} : Bool}) -> {Cmp.is_le(c) == True{} : Bool}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      Empty.absurd({True{} == True{} : Bool}, M1.clash(e))
    case GT{}:
      Empty.absurd({False{} == True{} : Bool}, M1.clash(e))

# a compare at most and not equal is LT
def le_ne_lt(
  c: Cmp,
  le: {Cmp.is_le(c) == True{} : Bool},
  ne: {Cmp.is_eq(c) == False{} : Bool}
) -> {Cmp.is_lt(c) == True{} : Bool}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      Empty.absurd({False{} == True{} : Bool}, M1.clash(Equal.sym(Bool, True{}, False{}, ne)))
    case GT{}:
      Empty.absurd({False{} == True{} : Bool}, M1.clash(le))

# a text below another is not equal to it, seen from the other side
def lt_ne(
  +a: String,
  +b: String,
  e: {String.is_lt(a, b) == True{} : Bool}
) -> {String.eq(b, a) == False{} : Bool}:
  %Equal.sym(Cmp, String.order.go(b, a, EQ{}),
    M7.cflip(String.order.go(a, b, EQ{})), M7.order_flip(a, b, EQ{}))
    : {Cmp.is_eq(_) == False{} : Bool}
  %Equal.sym(Cmp, String.order(a, b), LT{}, cmp_lt(String.order(a, b), e))
    : {Cmp.is_eq(M7.cflip(_)) == False{} : Bool}
  {==}

# a text is at most itself
def le_refl(+a: String) -> {String.is_le(a, a) == True{} : Bool}:
  %Equal.sym(Cmp, String.order.go(a, a, EQ{}), EQ{}, M5.order_refl(a))
    : {Cmp.is_le(_) == True{} : Bool}
  {==}

# a run's timestamp
def run.key(r: E.Excerpt.Run()) -> String:
  match r:
    case (t, _xs):
      t

# the timestamps of runs, in order
def keys(rs: List<&2, E.Excerpt.Run()>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{r, more}:
      run.key(r) <> keys(more)

# the excerpts of runs, in order
def flat(rs: List<&2, E.Excerpt.Run()>) -> List<&2, E.Ex>:
  match rs:
    case Nil{}:
      []
    case Con{r, more}:
      match r:
        case (_t, xs):
          List.append(&2, E.Ex, xs, flat(more))

# each run is a block of its timestamp
def keyed(rs: List<&2, E.Excerpt.Run()>) -> Data:
  match rs:
    case Nil{}:
      Unit
    case Con{r, more}:
      match r:
        case (t, xs):
          Sigma<&2, &2, M3.block(t, xs), _h => keyed(more)>

# a block's excerpts all have its timestamp
def block_all(-t: String, xs: List<&2, E.Ex>, hb: M3.block(t, xs)) -> M5.at_time(t, xs):
  match xs:
    case Nil{}:
      Empty.absurd(M5.at_time(t, []), hb)
    case Con{_x, _rest}:
      hb

# move a fact about a list of excerpts along an equation
def lcast(
  -T: List<&2, E.Ex> -> Type,
  -a: List<&2, E.Ex>,
  -b: List<&2, E.Ex>,
  e: {a == b : List<&2, E.Ex>},
  h: T(a)
) -> T(b):
  %e : T(_)
  h

# move a fact about a text along an equation
def scast(-T: String -> Type, -a: String, -b: String, e: {a == b : String}, h: T(a)) -> T(b):
  %e : T(_)
  h

# --- runs: what group makes ---

# a grouping step adds cur ahead of the excerpts, either way
def add_flat.at(
  b: Bool,
  +cur: E.Ex,
  +t: String,
  +r: List<&2, E.Ex>,
  +more: List<&2, E.Excerpt.Run()>
) -> {flat(E.Excerpt.group.if(b, cur, t, r, more))
  == cur <> List.append(&2, E.Ex, r, flat(more)) : List<&2, E.Ex>}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# grouping cur in puts it ahead of the excerpts
law add_flat:
  for +cur: E.Ex
  for rs: List<&2, E.Excerpt.Run()>
  {flat(E.Excerpt.group.add(cur, rs)) == cur <> flat(rs) : List<&2, E.Ex>}

def add_flat(cur, rs):
  match rs:
    case Nil{}:
      {==}
    case Con{first, +more}:
      match first:
        case (+t, +r):
          add_flat.at(String.eq(E.Excerpt.ts(E.Excerpt.rec(cur)), t), cur, t, r, more)

# the runs hold the excerpts, in order
law group_flat:
  for xs: List<&2, E.Ex>
  {flat(E.Excerpt.group(xs)) == xs : List<&2, E.Ex>}

def group_flat(xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(List<&2, E.Ex>, flat(E.Excerpt.group.add(x, E.Excerpt.group(rest))),
        x <> flat(E.Excerpt.group(rest)), add_flat(x, E.Excerpt.group(rest)))
        : {_ == x <> rest : List<&2, E.Ex>}
      Equal.cong(List<&2, E.Ex>, List<&2, E.Ex>, z => x <> z,
        flat(E.Excerpt.group(rest)), rest, group_flat(rest))

# cur grouped ahead of a first run of timestamp t, by whether cur has t
def group_ok.at(
  b: Bool,
  +cur: E.Ex,
  +t: String,
  +r0: E.Ex,
  +r1: List<&2, E.Ex>,
  +more: List<&2, E.Excerpt.Run()>,
  eb: {String.eq(E.Excerpt.ts(E.Excerpt.rec(cur)), t) == b : Bool},
  +h0: {D2.ex.ts(r0) == t : String},
  h1: M5.at_time(t, r1),
  hk: keyed(more),
  ha: {D2.ascending.from(keys(more), t) == True{} : Bool},
  le: {String.is_le(D2.ex.ts(cur), D2.ex.ts(r0)) == True{} : Bool}
) -> Pair({D2.ascending(keys(E.Excerpt.group.if(b, cur, t, r0 <> r1, more))) == True{}
  : Bool}, keyed(E.Excerpt.group.if(b, cur, t, r0 <> r1, more))):
  match b:
    case True{}:
      (ha, ((Equal.trans(String, D2.ex.ts(cur), E.Excerpt.ts(E.Excerpt.rec(cur)), t,
        Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(cur)), D2.ex.ts(cur), M6.ts_eq(cur)),
        eq_same(E.Excerpt.ts(E.Excerpt.rec(cur)), t, eb)), (h0, h1)), hk))
    case False{}:
      +kx = E.Excerpt.ts(E.Excerpt.rec(cur))
      +lek = {(%Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(cur)), D2.ex.ts(cur),
          M6.ts_eq(cur)) : {String.is_le(_, t) == True{} : Bool}
        %h0 : {String.is_le(D2.ex.ts(cur), _) == True{} : Bool}
        le) : {String.is_le(kx, t) == True{} : Bool}}
      (M6.and_tt(String.is_lt(kx, t), D2.ascending.from(keys(more), t),
        le_ne_lt(String.order(kx, t), lek, eb), ha),
        ((Equal.sym(String, kx, D2.ex.ts(cur), M6.ts_eq(cur)), Unit{}),
          ((h0, h1), hk)))

# a first run with no excerpts is no block
def empty_run(-t: String, -more: List<&2, E.Excerpt.Run()>, hk: keyed((t, []) <> more)) -> Empty:
  match hk:
    case (hb, _hm):
      hb

# group_ok.at with the first run's facts taken apart
def group_ok.split(
  +cur: E.Ex,
  +t: String,
  +r0: E.Ex,
  +r1: List<&2, E.Ex>,
  +more: List<&2, E.Excerpt.Run()>,
  ha: {D2.ascending.from(keys(more), t) == True{} : Bool},
  hk: keyed((t, r0 <> r1) <> more),
  hr: {Laws.rising.from(r0 <> List.append(&2, E.Ex, r1, flat(more)), D2.ex.ts(cur)) == True{} : Bool}
) -> Pair({D2.ascending(keys(E.Excerpt.group.add(cur, (t, r0 <> r1) <> more)))
  == True{} : Bool}, keyed(E.Excerpt.group.add(cur, (t, r0 <> r1) <> more))):
  match hk:
    case (hb, hm):
      match hb:
        case (h0, h1):
          group_ok.at(String.eq(E.Excerpt.ts(E.Excerpt.rec(cur)), t), cur, t,
            r0, r1, more, {==}, h0, h1, hm, ha,
            M1.and_l(String.is_le(D2.ex.ts(cur), D2.ex.ts(r0)),
              Laws.rising.from(List.append(&2, E.Ex, r1, flat(more)),
                D2.ex.ts(r0)), hr))

# cur grouped ahead of runs whose excerpts rise from cur keeps the runs'
# timestamps ascending and each run a block
def group_ok.add(
  +cur: E.Ex,
  rs: List<&2, E.Excerpt.Run()>,
  ha: {D2.ascending(keys(rs)) == True{} : Bool},
  hk: keyed(rs),
  hr: {Laws.rising.from(flat(rs), D2.ex.ts(cur)) == True{} : Bool}
) -> Pair({D2.ascending(keys(E.Excerpt.group.add(cur, rs))) == True{} : Bool},
  keyed(E.Excerpt.group.add(cur, rs))):
  match rs:
    case Nil{}:
      ({==}, ((Equal.sym(String, E.Excerpt.ts(E.Excerpt.rec(cur)), D2.ex.ts(cur),
        M6.ts_eq(cur)), Unit{}), Unit{}))
    case Con{first, +more}:
      match first:
        case (+t, r):
          match r:
            case Nil{}:
              Empty.absurd(Pair({D2.ascending(keys(E.Excerpt.group.add(cur,
                (t, []) <> more))) == True{} : Bool},
                keyed(E.Excerpt.group.add(cur, (t, []) <> more))), empty_run(t, more, hk))
            case Con{+r0, +r1}:
              group_ok.split(cur, t, r0, r1, more, ha, hk, hr)

# rising excerpts after prev are rising
def rising_tail(
  ys: List<&2, E.Ex>,
  +prev: String,
  h: {Laws.rising.from(ys, prev) == True{} : Bool}
) -> {Laws.rising(ys) == True{} : Bool}:
  match ys:
    case Nil{}:
      {==}
    case Con{+y, +rest}:
      M1.and_r(String.is_le(prev, D2.ex.ts(y)), Laws.rising.from(rest, D2.ex.ts(y)), h)

# group_ok's step, from what it says of the rest
def group_ok.ih(
  +x: E.Ex,
  +rest: List<&2, E.Ex>,
  h: {Laws.rising.from(rest, D2.ex.ts(x)) == True{} : Bool},
  ih: Pair({D2.ascending(keys(E.Excerpt.group(rest))) == True{} : Bool}, keyed(E.Excerpt.group(rest)))
) -> Pair({D2.ascending(keys(E.Excerpt.group(x <> rest))) == True{} : Bool},
  keyed(E.Excerpt.group(x <> rest))):
  match ih:
    case (ha, hk):
      group_ok.add(x, E.Excerpt.group(rest), ha, hk,
        lcast(l => {Laws.rising.from(l, D2.ex.ts(x)) == True{} : Bool}, rest,
          flat(E.Excerpt.group(rest)),
          Equal.sym(List<&2, E.Ex>, flat(E.Excerpt.group(rest)), rest, group_flat(rest)),
          h))

# rising excerpts group into runs of ascending timestamps, each a block
law group_ok:
  for xs: List<&2, E.Ex>
  for +h: {Laws.rising(xs) == True{} : Bool}
  Pair({D2.ascending(keys(E.Excerpt.group(xs))) == True{} : Bool},
    keyed(E.Excerpt.group(xs)))

def group_ok(xs, h):
  match xs:
    case Nil{}:
      ({==}, Unit{})
    case Con{+x, +rest}:
      group_ok.ih(x, rest, h, group_ok(rest, rising_tail(rest, D2.ex.ts(x), h)))

# --- runs: what a joined run holds ---

# the first ones of excerpts of time t are of time t, either way
def all_firsts.at(
  b: Bool,
  -t: String,
  -x: E.Ex,
  -fl: List<&2, E.Ex>,
  px: {D2.ex.ts(x) == t : String},
  a: M5.at_time(t, fl)
) -> M5.at_time(t, E.Excerpt.firsts.if(b, x, fl)):
  match b:
    case True{}:
      a
    case False{}:
      (px, a)

# the first excerpt of each record among excerpts of time t is of time t
law all_firsts:
  for -t: String
  for xs: List<&2, E.Ex>
  for +seen: List<&2, String>
  for h: M5.at_time(t, xs)
  M5.at_time(t, E.Excerpt.firsts(xs, seen))

def all_firsts(t, xs, seen, h):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, rest}:
      match h:
        case (px, hr):
          all_firsts.at(E.Excerpt.named(E.Excerpt.id(E.Excerpt.rec(x)), seen), t, x,
            E.Excerpt.firsts(rest, E.Excerpt.id(E.Excerpt.rec(x)) <> seen), px,
            all_firsts(t, rest, E.Excerpt.id(E.Excerpt.rec(x)) <> seen, hr))

# joining keeps each excerpt's timestamp
law all_join_ts:
  for -t: String
  for fs: List<&2, E.Ex>
  for +all: List<&2, E.Ex>
  for h: M5.at_time(t, fs)
  M5.at_time(t, E.Excerpt.join(fs, all))

def all_join_ts(t, fs, all, h):
  match fs:
    case Nil{}:
      Unit{}
    case Con{f, rest}:
      match f:
        case E.Ex{+rec, _ps}:
          match h:
            case (hf, hr):
              (hf, all_join_ts(t, rest, all, hr))

# a block's run is a block of the same timestamp
law run_block:
  for -t: String
  for r: List<&2, E.Ex>
  for hb: M3.block(t, r)
  M3.block(t, E.Excerpt.run(r))

def run_block(t, r, hb):
  match r:
    case Nil{}:
      Empty.absurd(M3.block(t, E.Excerpt.run([])), hb)
    case Con{r0, +r1}:
      match r0:
        case E.Ex{+rec, +ps}:
          match hb:
            case (h0, h1):
              (h0, all_join_ts(t, E.Excerpt.firsts(r1, [E.Excerpt.id(rec)]),
                E.Ex{rec, ps} <> r1,
                all_firsts(t, r1,
                  [E.Excerpt.id(rec)], h1)))

# --- merge_sorted ---

# excerpts all of time t, then excerpts rising from t, rise from t
law rise_eq:
  for xs: List<&2, E.Ex>
  for +ys: List<&2, E.Ex>
  for +t: String
  for hx: M5.at_time(t, xs)
  for hy: {Laws.rising.from(ys, t) == True{} : Bool}
  {Laws.rising.from(List.append(&2, E.Ex, xs, ys), t) == True{} : Bool}

def rise_eq(xs, ys, t, hx, hy):
  match xs:
    case Nil{}:
      hy
    case Con{+a, +rest}:
      match hx:
        case (+ha, hr):
          %Equal.sym(String, D2.ex.ts(a), t, ha)
            : {Bool.and(String.is_le(t, _),
              Laws.rising.from(List.append(&2, E.Ex, rest, ys), _)) == True{} : Bool}
          M6.and_tt(String.is_le(t, t), Laws.rising.from(List.append(&2, E.Ex, rest, ys), t),
            le_refl(t), rise_eq(rest, ys, t, hr, hy))

# a block of time t at or after prev, then excerpts rising from t, rise
# from prev
law rise_block:
  for xs: List<&2, E.Ex>
  for +ys: List<&2, E.Ex>
  for +prev: String
  for +t: String
  for hb: M3.block(t, xs)
  for hp: {String.is_le(prev, t) == True{} : Bool}
  for hy: {Laws.rising.from(ys, t) == True{} : Bool}
  {Laws.rising.from(List.append(&2, E.Ex, xs, ys), prev) == True{} : Bool}

def rise_block(xs, ys, prev, t, hb, hp, hy):
  match xs:
    case Nil{}:
      Empty.absurd({Laws.rising.from(ys, prev) == True{} : Bool}, hb)
    case Con{+a, +rest}:
      match hb:
        case (+ha, hr):
          %Equal.sym(String, D2.ex.ts(a), t, ha)
            : {Bool.and(String.is_le(prev, _),
              Laws.rising.from(List.append(&2, E.Ex, rest, ys), _)) == True{} : Bool}
          M6.and_tt(String.is_le(prev, t),
            Laws.rising.from(List.append(&2, E.Ex, rest, ys), t), hp,
            rise_eq(rest, ys, t, hr, hy))

# a block of time t, then excerpts rising from t, rise
law rise_block0:
  for xs: List<&2, E.Ex>
  for +ys: List<&2, E.Ex>
  for +t: String
  for hb: M3.block(t, xs)
  for hy: {Laws.rising.from(ys, t) == True{} : Bool}
  {Laws.rising(List.append(&2, E.Ex, xs, ys)) == True{} : Bool}

def rise_block0(xs, ys, t, hb, hy):
  match xs:
    case Nil{}:
      Empty.absurd({Laws.rising(ys) == True{} : Bool}, hb)
    case Con{+a, +rest}:
      match hb:
        case (+ha, hr):
          %Equal.sym(String, D2.ex.ts(a), t, ha)
            : {Laws.rising.from(List.append(&2, E.Ex, rest, ys), _) == True{} : Bool}
          rise_eq(rest, ys, t, hr, hy)

# joined runs of timestamps ascending from t rise from t
law joined_from:
  for rs: List<&2, E.Excerpt.Run()>
  for +t: String
  for +hk: {D2.ascending.from(keys(rs), t) == True{} : Bool}
  for hd: keyed(rs)
  {Laws.rising.from(E.Excerpt.joined(rs), t) == True{} : Bool}

def joined_from(rs, t, hk, hd):
  match rs:
    case Nil{}:
      {==}
    case Con{first, +more}:
      match first:
        case (+t2, +r2):
          match hd:
            case (hb, hm):
              rise_block(E.Excerpt.run(r2), E.Excerpt.joined(more), t, t2,
                run_block(t2, r2, hb),
                lt_le(String.order(t, t2), M1.and_l(String.is_lt(t, t2),
                  D2.ascending.from(keys(more), t2), hk)),
                joined_from(more, t2, M1.and_r(String.is_lt(t, t2),
                  D2.ascending.from(keys(more), t2), hk), hm))

# joined runs of ascending timestamps rise
law joined_rising:
  for rs: List<&2, E.Excerpt.Run()>
  for hk: {D2.ascending(keys(rs)) == True{} : Bool}
  for hd: keyed(rs)
  {Laws.rising(E.Excerpt.joined(rs)) == True{} : Bool}

def joined_rising(rs, hk, hd):
  match rs:
    case Nil{}:
      {==}
    case Con{first, +more}:
      match first:
        case (+t, +r):
          match hd:
            case (hb, hm):
              rise_block0(E.Excerpt.run(r), E.Excerpt.joined(more), t,
                run_block(t, r, hb), joined_from(more, t, hk, hm))

# the sorted excerpts' runs, joined, rise
def merged_rising(
  +ys: List<&2, E.Ex>,
  ok: Pair({D2.ascending(keys(E.Excerpt.group(ys))) == True{} : Bool}, keyed(E.Excerpt.group(ys)))
) -> {Laws.rising(E.Excerpt.joined(E.Excerpt.group(ys))) == True{} : Bool}:
  match ok:
    case (hk, hd):
      joined_rising(E.Excerpt.group(ys), hk, hd)

def Laws.merge_sorted(xs):
  +all = List.concat(&2, E.Ex, xs)
  merged_rising(E.Excerpt.sort(all), group_ok(E.Excerpt.sort(all), sort_rising(all)))

# --- merge_holds ---

# an append holds what either side holds
law holds_app:
  for +id: String
  for +n: U32
  for xs: List<&2, E.Ex>
  for +ys: List<&2, E.Ex>
  {D2.holds(id, n, List.append(&2, E.Ex, xs, ys))
    == Bool.or(D2.holds(id, n, xs), D2.holds(id, n, ys)) : Bool}

def holds_app(id, n, xs, ys):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(Bool, D2.holds(id, n, List.append(&2, E.Ex, rest, ys)),
        Bool.or(D2.holds(id, n, rest), D2.holds(id, n, ys)), holds_app(id, n, rest, ys))
        : {Bool.or(Bool.and(String.eq(D2.rec.id(D2.ex.rec(x)), id),
          D2.numbered(n, D2.ex.paras(x))), _)
          == Bool.or(D2.holds(id, n, x <> rest), D2.holds(id, n, ys)) : Bool}
      or_assoc(Bool.and(String.eq(D2.rec.id(D2.ex.rec(x)), id),
        D2.numbered(n, D2.ex.paras(x))), D2.holds(id, n, rest),
        D2.holds(id, n, ys))

# a joined run holds what the run holds
law holds_run:
  for +id: String
  for +n: U32
  for +r: List<&2, E.Ex>
  {D2.holds(id, n, E.Excerpt.run(r)) == D2.holds(id, n, r) : Bool}

def holds_run(id, n, r):
  +fs = E.Excerpt.firsts(r, [])
  %Equal.sym(Bool, D2.holds(id, n, E.Excerpt.join(fs, r)),
    Bool.and(M2.ids(id, fs), D2.holds(id, n, r)), holds_join(id, n, fs, r))
    : {_ == D2.holds(id, n, r) : Bool}
  %Equal.sym(List<&2, E.Ex>, fs, Laws.firsts(r, []), firsts_eq(r, []))
    : {Bool.and(M2.ids(id, _), D2.holds(id, n, r)) == D2.holds(id, n, r) : Bool}
  %Equal.sym(Bool, M2.ids(id, Laws.firsts(r, [])), M2.ids(id, r), ids_firsts(id, r, []))
    : {Bool.and(_, D2.holds(id, n, r)) == D2.holds(id, n, r) : Bool}
  holds_ids(id, n, r)

# joined runs hold what the runs hold
law holds_runs:
  for +id: String
  for +n: U32
  for rs: List<&2, E.Excerpt.Run()>
  {D2.holds(id, n, E.Excerpt.joined(rs)) == D2.holds(id, n, flat(rs)) : Bool}

def holds_runs(id, n, rs):
  match rs:
    case Nil{}:
      {==}
    case Con{first, +more}:
      match first:
        case (_t, +r):
          %Equal.sym(Bool, D2.holds(id, n, List.append(&2, E.Ex, E.Excerpt.run(r),
            E.Excerpt.joined(more))), Bool.or(D2.holds(id, n, E.Excerpt.run(r)),
            D2.holds(id, n, E.Excerpt.joined(more))),
            holds_app(id, n, E.Excerpt.run(r), E.Excerpt.joined(more)))
            : {_ == D2.holds(id, n, List.append(&2, E.Ex, r, flat(more))) : Bool}
          %Equal.sym(Bool, D2.holds(id, n, List.append(&2, E.Ex, r, flat(more))),
            Bool.or(D2.holds(id, n, r), D2.holds(id, n, flat(more))),
            holds_app(id, n, r, flat(more)))
            : {Bool.or(D2.holds(id, n, E.Excerpt.run(r)),
              D2.holds(id, n, E.Excerpt.joined(more))) == _ : Bool}
          %Equal.sym(Bool, D2.holds(id, n, E.Excerpt.run(r)), D2.holds(id, n, r),
            holds_run(id, n, r))
            : {Bool.or(_, D2.holds(id, n, E.Excerpt.joined(more)))
              == Bool.or(D2.holds(id, n, r), D2.holds(id, n, flat(more))) : Bool}
          Equal.cong(Bool, Bool, z => Bool.or(D2.holds(id, n, r), z),
            D2.holds(id, n, E.Excerpt.joined(more)), D2.holds(id, n, flat(more)),
            holds_runs(id, n, more))

def Laws.merge_holds(xs, id, n):
  +all = List.concat(&2, E.Ex, xs)
  +ss = E.Excerpt.sort(all)
  %Equal.sym(Bool, D2.holds(id, n, E.Excerpt.joined(E.Excerpt.group(ss))),
    D2.holds(id, n, flat(E.Excerpt.group(ss))), holds_runs(id, n, E.Excerpt.group(ss)))
    : {_ == D2.holds(id, n, all) : Bool}
  %Equal.sym(List<&2, E.Ex>, flat(E.Excerpt.group(ss)), ss, group_flat(ss))
    : {D2.holds(id, n, _) == D2.holds(id, n, all) : Bool}
  holds_sort(id, n, all)

# --- merge_paras and merge_verbatim ---

# what is among one list ahead of another is among one of them
def elem_split.at(
  -z: E.Ex,
  -a: E.Ex,
  -xs: List<&2, E.Ex>,
  -ys: List<&2, E.Ex>,
  o: Or(D1.Elem(E.Ex, z, xs), D1.Elem(E.Ex, z, ys))
) -> Or(D1.Elem(E.Ex, z, a <> xs), D1.Elem(E.Ex, z, ys)):
  match o:
    case Inl{el}:
      Inl{Inr{el}}
    case Inr{el}:
      Inr{el}

# what is among an append is among one side
law elem_split:
  for -z: E.Ex
  for xs: List<&2, E.Ex>
  for -ys: List<&2, E.Ex>
  for h: D1.Elem(E.Ex, z, List.append(&2, E.Ex, xs, ys))
  Or(D1.Elem(E.Ex, z, xs), D1.Elem(E.Ex, z, ys))

def elem_split(z, xs, ys, h):
  match xs:
    case Nil{}:
      Inr{h}
    case Con{a, rest}:
      match h:
        case Inl{e}:
          Inl{Inl{e}}
        case Inr{el}:
          elem_split.at(z, a, rest, ys, elem_split(z, rest, ys, el))

# what is among the left side is among an append
law elem_left:
  for -z: E.Ex
  for xs: List<&2, E.Ex>
  for -ys: List<&2, E.Ex>
  for h: D1.Elem(E.Ex, z, xs)
  D1.Elem(E.Ex, z, List.append(&2, E.Ex, xs, ys))

def elem_left(z, xs, ys, h):
  match xs:
    case Nil{}:
      Empty.absurd(D1.Elem(E.Ex, z, ys), h)
    case Con{_a, rest}:
      match h:
        case Inl{e}:
          Inl{e}
        case Inr{el}:
          Inr{elem_left(z, rest, ys, el)}

# what is among the right side is among an append
law elem_right:
  for -z: E.Ex
  for xs: List<&2, E.Ex>
  for -ys: List<&2, E.Ex>
  for h: D1.Elem(E.Ex, z, ys)
  D1.Elem(E.Ex, z, List.append(&2, E.Ex, xs, ys))

def elem_right(z, xs, ys, h):
  match xs:
    case Nil{}:
      h
    case Con{_a, rest}:
      Inr{elem_right(z, rest, ys, h)}

# an excerpt from one list is one from another, when every member is
def src_map(
  -q: P.Para,
  -i: String,
  -xs: List<&2, E.Ex>,
  -ys: List<&2, E.Ex>,
  f: @y: E.Ex -> D1.Elem(E.Ex, y, xs) -> D1.Elem(E.Ex, y, ys),
  o: src_of(q, i, xs)
) -> src_of(q, i, ys):
  match o:
    case (+y, pr):
      match pr:
        case (el, r):
          (y, (f(y, el), r))

# a joined run's excerpt climbs, or a later one does
def joined_paras.at(
  +x: E.Ex,
  +r: List<&2, E.Ex>,
  -more: List<&2, E.Excerpt.Run()>,
  ih: D1.Elem(E.Ex, x, E.Excerpt.joined(more)) -> {Laws.climbing(D2.ex.paras(x)) == True{} : Bool},
  o: Or(D1.Elem(E.Ex, x, E.Excerpt.run(r)), D1.Elem(E.Ex, x, E.Excerpt.joined(more)))
) -> {Laws.climbing(D2.ex.paras(x)) == True{} : Bool}:
  match o:
    case Inl{el}:
      %Equal.sym(List<&2, P.Para>, D2.ex.paras(x),
        E.Excerpt.gather(D2.rec.id(D2.ex.rec(x)), r),
        elem_join(x, E.Excerpt.firsts(r, []), r, el))
        : {Laws.climbing(_) == True{} : Bool}
      gather_climbing(D2.rec.id(D2.ex.rec(x)), r)
    case Inr{el}:
      ih(el)

# every excerpt of joined runs climbs
law joined_paras:
  for +x: E.Ex
  for rs: List<&2, E.Excerpt.Run()>
  for h: D1.Elem(E.Ex, x, E.Excerpt.joined(rs))
  {Laws.climbing(D2.ex.paras(x)) == True{} : Bool}

def joined_paras(x, rs, h):
  match rs:
    case Nil{}:
      Empty.absurd({Laws.climbing(D2.ex.paras(x)) == True{} : Bool}, h)
    case Con{first, +more}:
      match first:
        case (_t, +r):
          joined_paras.at(x, r, more, hh => joined_paras(x, more, hh),
            elem_split(x, E.Excerpt.run(r), E.Excerpt.joined(more), h))

def Laws.merge_paras(xs, x, hx):
  +all = List.concat(&2, E.Ex, xs)
  joined_paras(x, E.Excerpt.group(E.Excerpt.sort(all)), hx)

# what joined_src says of the later runs
def src_ih(x: E.Ex, q: P.Para, more: List<&2, E.Excerpt.Run()>) -> Type:
  D1.Elem(E.Ex, x, E.Excerpt.joined(more)) -> D1.Elem(P.Para, q, D2.ex.paras(x))
    -> src_of(q, D2.rec.id(D2.ex.rec(x)), flat(more))

# a joined run's paragraph has its excerpt in the run, or a later one does
def joined_src.at(
  +x: E.Ex,
  -q: P.Para,
  +r: List<&2, E.Ex>,
  +more: List<&2, E.Excerpt.Run()>,
  hq: D1.Elem(P.Para, q, D2.ex.paras(x)),
  ih: src_ih(x, q, more),
  o: Or(D1.Elem(E.Ex, x, E.Excerpt.run(r)), D1.Elem(E.Ex, x, E.Excerpt.joined(more)))
) -> src_of(q, D2.rec.id(D2.ex.rec(x)), List.append(&2, E.Ex, r, flat(more))):
  match o:
    case Inl{el}:
      src_map(q, D2.rec.id(D2.ex.rec(x)), r, List.append(&2, E.Ex, r, flat(more)),
        y => e => elem_left(y, r, flat(more), e),
        elem_gather(q, D2.rec.id(D2.ex.rec(x)), r,
          M4.elem_cast(P.Para, q, D2.ex.paras(x),
            E.Excerpt.gather(D2.rec.id(D2.ex.rec(x)), r),
            elem_join(x, E.Excerpt.firsts(r, []), r, el), hq)))
    case Inr{el}:
      src_map(q, D2.rec.id(D2.ex.rec(x)), flat(more),
        List.append(&2, E.Ex, r, flat(more)),
        y => e => elem_right(y, r, flat(more), e), ih(el, hq))

# every paragraph of joined runs has an excerpt of its record among the runs
law joined_src:
  for +x: E.Ex
  for rs: List<&2, E.Excerpt.Run()>
  for h: D1.Elem(E.Ex, x, E.Excerpt.joined(rs))
  for -q: P.Para
  for hq: D1.Elem(P.Para, q, D2.ex.paras(x))
  src_of(q, D2.rec.id(D2.ex.rec(x)), flat(rs))

def joined_src(x, rs, h, q, hq):
  match rs:
    case Nil{}:
      Empty.absurd(src_of(q, D2.rec.id(D2.ex.rec(x)), []), h)
    case Con{first, +more}:
      match first:
        case (_t, +r):
          joined_src.at(x, q, r, more, hq, hh => hq2 => joined_src(x, more, hh, q, hq2),
            elem_split(x, E.Excerpt.run(r), E.Excerpt.joined(more), h))

def Laws.merge_verbatim(xs, x, hx, q, hq):
  +all = List.concat(&2, E.Ex, xs)
  +ss = E.Excerpt.sort(all)
  src_map(q, D2.rec.id(D2.ex.rec(x)), ss, all, y => e => elem_sort(y, all, e),
    lcast(l => src_of(q, D2.rec.id(D2.ex.rec(x)), l), flat(E.Excerpt.group(ss)), ss,
      group_flat(ss), joined_src(x, E.Excerpt.group(ss), hx, q, hq)))

# --- merge_stable ---

# a filter put ahead of an append, either way
def only_app.at(
  b: Bool,
  +a: E.Ex,
  -x: List<&2, E.Ex>,
  -y: List<&2, E.Ex>,
  -z: List<&2, E.Ex>,
  e: {x == List.append(&2, E.Ex, y, z) : List<&2, E.Ex>}
) -> {List.filter.put(E.Ex, a, x, b)
  == List.append(&2, E.Ex, List.filter.put(E.Ex, a, y, b), z) : List<&2, E.Ex>}:
  match b:
    case True{}:
      Equal.cong(List<&2, E.Ex>, List<&2, E.Ex>, w => a <> w, x,
        List.append(&2, E.Ex, y, z), e)
    case False{}:
      e

# the excerpts of time t of an append are those of each side
law only_app:
  for +t: String
  for xs: List<&2, E.Ex>
  for +ys: List<&2, E.Ex>
  {D2.only(t, List.append(&2, E.Ex, xs, ys))
    == List.append(&2, E.Ex, D2.only(t, xs), D2.only(t, ys)) : List<&2, E.Ex>}

def only_app(t, xs, ys):
  match xs:
    case Nil{}:
      {==}
    case Con{+a, +rest}:
      only_app.at(String.eq(D2.ex.ts(a), t), a,
        D2.only(t, List.append(&2, E.Ex, rest, ys)), D2.only(t, rest),
        D2.only(t, ys), only_app(t, rest, ys))

# excerpts none of time t have no excerpts of time t
law only_none:
  for +t: String
  for xs: List<&2, E.Ex>
  for h: M1.apart(t, xs)
  {D2.only(t, xs) == [] : List<&2, E.Ex>}

def only_none(t, xs, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+a, +rest}:
      match h:
        case (ha, hr):
          %Equal.sym(Bool, String.eq(D2.ex.ts(a), t), False{}, ha)
            : {List.filter.put(E.Ex, a, D2.only(t, rest), _) == [] : List<&2, E.Ex>}
          only_none(t, rest, hr)

# excerpts all of time t2 are none of time k when t2 is not k
law apart_block:
  for -k: String
  for -t2: String
  for xs: List<&2, E.Ex>
  for h: M5.at_time(t2, xs)
  for +hne: {String.eq(t2, k) == False{} : Bool}
  M1.apart(k, xs)

def apart_block(k, t2, xs, h, hne):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+a, +rest}:
      match h:
        case (ha, hr):
          ((%Equal.sym(String, D2.ex.ts(a), t2, ha)
            : {String.eq(_, k) == False{} : Bool}
            hne), apart_block(k, t2, rest, hr, hne))

# excerpts none of time k, appended, are none of time k
law apart_app:
  for -k: String
  for xs: List<&2, E.Ex>
  for -ys: List<&2, E.Ex>
  for hx: M1.apart(k, xs)
  for hy: M1.apart(k, ys)
  M1.apart(k, List.append(&2, E.Ex, xs, ys))

def apart_app(k, xs, ys, hx, hy):
  match xs:
    case Nil{}:
      hy
    case Con{_a, rest}:
      match hx:
        case (ha, hr):
          (ha, apart_app(k, rest, ys, hr, hy))

# timestamps ascending from k2, with k below k2, ascend from k
law asc_lower:
  for ks: List<&2, String>
  for +k: String
  for +k2: String
  for hl: {String.is_lt(k, k2) == True{} : Bool}
  for +ha: {D2.ascending.from(ks, k2) == True{} : Bool}
  {D2.ascending.from(ks, k) == True{} : Bool}

def asc_lower(ks, k, k2, hl, ha):
  match ks:
    case Nil{}:
      {==}
    case Con{+k3, +rest}:
      M6.and_tt(String.is_lt(k, k3), D2.ascending.from(rest, k3),
        lt_trans(k, k2, k3, hl, M1.and_l(String.is_lt(k2, k3),
          D2.ascending.from(rest, k3), ha)),
        M1.and_r(String.is_lt(k2, k3), D2.ascending.from(rest, k3), ha))

# above_runs' step, from what it says of the later runs
def above_runs.at(
  -k: String,
  -t2: String,
  +r2: List<&2, E.Ex>,
  +more: List<&2, E.Excerpt.Run()>,
  +hb: M3.block(t2, r2),
  +hne: {String.eq(t2, k) == False{} : Bool},
  ih: Pair(M1.apart(k, E.Excerpt.joined(more)), M1.apart(k, flat(more)))
) -> Pair(M1.apart(k, List.append(&2, E.Ex, E.Excerpt.run(r2), E.Excerpt.joined(more))),
  M1.apart(k, List.append(&2, E.Ex, r2, flat(more)))):
  match ih:
    case (aj, af):
      (apart_app(k, E.Excerpt.run(r2), E.Excerpt.joined(more),
        apart_block(k, t2, E.Excerpt.run(r2),
          block_all(t2, E.Excerpt.run(r2), run_block(t2, r2, hb)), hne), aj),
        apart_app(k, r2, flat(more), apart_block(k, t2, r2, block_all(t2, r2, hb), hne),
          af))

# runs of timestamps above k hold no excerpt of time k, joined or not
law above_runs:
  for rs: List<&2, E.Excerpt.Run()>
  for +k: String
  for +hk: {D2.ascending.from(keys(rs), k) == True{} : Bool}
  for hd: keyed(rs)
  Pair(M1.apart(k, E.Excerpt.joined(rs)), M1.apart(k, flat(rs)))

def above_runs(rs, k, hk, hd):
  match rs:
    case Nil{}:
      (Unit{}, Unit{})
    case Con{first, +more}:
      match first:
        case (+t2, +r2):
          match hd:
            case (hb, hm):
              above_runs.at(k, t2, r2, more, hb,
                lt_ne(k, t2, M1.and_l(String.is_lt(k, t2),
                  D2.ascending.from(keys(more), t2), hk)),
                above_runs(more, k, asc_lower(keys(more), k, t2,
                  M1.and_l(String.is_lt(k, t2), D2.ascending.from(keys(more), t2), hk),
                  M1.and_r(String.is_lt(k, t2), D2.ascending.from(keys(more), t2), hk)), hm))

# joining keeps the first excerpts' records, in order
law recs_join:
  for fs: List<&2, E.Ex>
  for +all: List<&2, E.Ex>
  {D2.recs(E.Excerpt.join(fs, all)) == D2.recs(fs) : List<&2, R.Record>}

def recs_join(fs, all):
  match fs:
    case Nil{}:
      {==}
    case Con{f, +rest}:
      match f:
        case E.Ex{+rec, _ps}:
          Equal.cong(List<&2, R.Record>, List<&2, R.Record>, z => rec <> z,
            D2.recs(E.Excerpt.join(rest, all)), D2.recs(rest), recs_join(rest, all))

# timestamps ascending from k ascend
def asc_tail(
  ks: List<&2, String>,
  +k: String,
  h: {D2.ascending.from(ks, k) == True{} : Bool}
) -> {D2.ascending(ks) == True{} : Bool}:
  match ks:
    case Nil{}:
      {==}
    case Con{+k2, +rest}:
      M1.and_r(String.is_lt(k, k2), D2.ascending.from(rest, k2), h)

# the run of time t: its excerpts of time t are the run, and no later run
# has any
def stable_true(
  +t: String,
  +r: List<&2, E.Ex>,
  +more: List<&2, E.Excerpt.Run()>,
  at_r: M5.at_time(t, r),
  at_run: M5.at_time(t, E.Excerpt.run(r)),
  ab: Pair(M1.apart(t, E.Excerpt.joined(more)), M1.apart(t, flat(more)))
) -> {D2.recs(List.append(&2, E.Ex, D2.only(t, E.Excerpt.run(r)),
    D2.only(t, E.Excerpt.joined(more))))
  == D2.recs(Laws.firsts(List.append(&2, E.Ex, D2.only(t, r),
    D2.only(t, flat(more))), [])) : List<&2, R.Record>}:
  match ab:
    case (aj, af):
      %Equal.sym(List<&2, E.Ex>, D2.only(t, E.Excerpt.run(r)), E.Excerpt.run(r),
        M5.only_all(t, E.Excerpt.run(r), at_run))
        : {D2.recs(List.append(&2, E.Ex, _, D2.only(t, E.Excerpt.joined(more))))
          == D2.recs(Laws.firsts(List.append(&2, E.Ex, D2.only(t, r),
            D2.only(t, flat(more))), [])) : List<&2, R.Record>}
      %Equal.sym(List<&2, E.Ex>, D2.only(t, E.Excerpt.joined(more)), [],
        only_none(t, E.Excerpt.joined(more), aj))
        : {D2.recs(List.append(&2, E.Ex, E.Excerpt.run(r), _))
          == D2.recs(Laws.firsts(List.append(&2, E.Ex, D2.only(t, r),
            D2.only(t, flat(more))), [])) : List<&2, R.Record>}
      %Equal.sym(List<&2, E.Ex>, D2.only(t, r), r, M5.only_all(t, r, at_r))
        : {D2.recs(List.append(&2, E.Ex, E.Excerpt.run(r), []))
          == D2.recs(Laws.firsts(List.append(&2, E.Ex, _,
            D2.only(t, flat(more))), [])) : List<&2, R.Record>}
      %Equal.sym(List<&2, E.Ex>, D2.only(t, flat(more)), [],
        only_none(t, flat(more), af))
        : {D2.recs(List.append(&2, E.Ex, E.Excerpt.run(r), []))
          == D2.recs(Laws.firsts(List.append(&2, E.Ex, r, _), []))
          : List<&2, R.Record>}
      %Equal.sym(List<&2, E.Ex>, List.append(&2, E.Ex, E.Excerpt.run(r), []),
        E.Excerpt.run(r), M4.lapp_nil(E.Ex, E.Excerpt.run(r)))
        : {D2.recs(_) == D2.recs(Laws.firsts(List.append(&2, E.Ex, r, []), []))
          : List<&2, R.Record>}
      %Equal.sym(List<&2, E.Ex>, List.append(&2, E.Ex, r, []), r, M4.lapp_nil(E.Ex, r))
        : {D2.recs(E.Excerpt.run(r)) == D2.recs(Laws.firsts(_, []))
          : List<&2, R.Record>}
      %Equal.sym(List<&2, R.Record>, D2.recs(E.Excerpt.join(E.Excerpt.firsts(r, []), r)),
        D2.recs(E.Excerpt.firsts(r, [])), recs_join(E.Excerpt.firsts(r, []), r))
        : {_ == D2.recs(Laws.firsts(r, [])) : List<&2, R.Record>}
      Equal.cong(List<&2, E.Ex>, List<&2, R.Record>, z => D2.recs(z),
        E.Excerpt.firsts(r, []), Laws.firsts(r, []), firsts_eq(r, []))

# what stable_runs says of the later runs
def stable_ih(t: String, more: List<&2, E.Excerpt.Run()>) -> Type:
  {D2.recs(D2.only(t, E.Excerpt.joined(more)))
    == D2.recs(Laws.firsts(D2.only(t, flat(more)), [])) : List<&2, R.Record>}

# the first run's share of time t, by whether it is the run of time t
def stable_at(
  b: Bool,
  +t: String,
  +k: String,
  +r: List<&2, E.Ex>,
  +more: List<&2, E.Excerpt.Run()>,
  +eb: {String.eq(k, t) == b : Bool},
  +hb: M3.block(k, r),
  +hm: keyed(more),
  +hk: {D2.ascending.from(keys(more), k) == True{} : Bool},
  ih: stable_ih(t, more)
) -> {D2.recs(List.append(&2, E.Ex, D2.only(t, E.Excerpt.run(r)),
    D2.only(t, E.Excerpt.joined(more))))
  == D2.recs(Laws.firsts(List.append(&2, E.Ex, D2.only(t, r),
    D2.only(t, flat(more))), [])) : List<&2, R.Record>}:
  match b:
    case True{}:
      +ekt = eq_same(k, t, eb)
      stable_true(t, r, more,
        scast(z => M5.at_time(z, r), k, t, ekt, block_all(k, r, hb)),
        scast(z => M5.at_time(z, E.Excerpt.run(r)), k, t, ekt,
          block_all(k, E.Excerpt.run(r), run_block(k, r, hb))),
        scast(z => Pair(M1.apart(z, E.Excerpt.joined(more)), M1.apart(z, flat(more))), k, t,
          ekt, above_runs(more, k, hk, hm)))
    case False{}:
      %Equal.sym(List<&2, E.Ex>, D2.only(t, E.Excerpt.run(r)), [],
        only_none(t, E.Excerpt.run(r), apart_block(t, k, E.Excerpt.run(r),
          block_all(k, E.Excerpt.run(r), run_block(k, r, hb)), eb)))
        : {D2.recs(List.append(&2, E.Ex, _, D2.only(t, E.Excerpt.joined(more))))
          == D2.recs(Laws.firsts(List.append(&2, E.Ex, D2.only(t, r),
            D2.only(t, flat(more))), [])) : List<&2, R.Record>}
      %Equal.sym(List<&2, E.Ex>, D2.only(t, r), [],
        only_none(t, r, apart_block(t, k, r, block_all(k, r, hb), eb)))
        : {D2.recs(D2.only(t, E.Excerpt.joined(more)))
          == D2.recs(Laws.firsts(List.append(&2, E.Ex, _,
            D2.only(t, flat(more))), [])) : List<&2, R.Record>}
      ih

# for every time, joined runs of ascending timestamps hold the first
# excerpt of each record among the runs' excerpts of that time
law stable_runs:
  for +t: String
  for rs: List<&2, E.Excerpt.Run()>
  for +hk: {D2.ascending(keys(rs)) == True{} : Bool}
  for hd: keyed(rs)
  {D2.recs(D2.only(t, E.Excerpt.joined(rs)))
    == D2.recs(Laws.firsts(D2.only(t, flat(rs)), [])) : List<&2, R.Record>}

def stable_runs(t, rs, hk, hd):
  match rs:
    case Nil{}:
      {==}
    case Con{first, +more}:
      match first:
        case (+k, +r):
          match hd:
            case (+hb, +hm):
              %Equal.sym(List<&2, E.Ex>,
                D2.only(t, List.append(&2, E.Ex, E.Excerpt.run(r), E.Excerpt.joined(more))),
                List.append(&2, E.Ex, D2.only(t, E.Excerpt.run(r)),
                  D2.only(t, E.Excerpt.joined(more))),
                only_app(t, E.Excerpt.run(r), E.Excerpt.joined(more)))
                : {D2.recs(_) == D2.recs(Laws.firsts(D2.only(t,
                  List.append(&2, E.Ex, r, flat(more))), [])) : List<&2, R.Record>}
              %Equal.sym(List<&2, E.Ex>, D2.only(t, List.append(&2, E.Ex, r, flat(more))),
                List.append(&2, E.Ex, D2.only(t, r), D2.only(t, flat(more))),
                only_app(t, r, flat(more)))
                : {D2.recs(List.append(&2, E.Ex, D2.only(t, E.Excerpt.run(r)),
                  D2.only(t, E.Excerpt.joined(more))))
                  == D2.recs(Laws.firsts(_, [])) : List<&2, R.Record>}
              stable_at(String.eq(k, t), t, k, r, more, {==}, hb, hm, hk,
                stable_runs(t, more, asc_tail(keys(more), k, hk), hm))

# stable_runs from what group_ok says
def stable_runs.ok(
  +t: String,
  +ys: List<&2, E.Ex>,
  ok: Pair({D2.ascending(keys(E.Excerpt.group(ys))) == True{} : Bool}, keyed(E.Excerpt.group(ys)))
) -> {D2.recs(D2.only(t, E.Excerpt.joined(E.Excerpt.group(ys))))
  == D2.recs(Laws.firsts(D2.only(t, flat(E.Excerpt.group(ys))), []))
  : List<&2, R.Record>}:
  match ok:
    case (hk, hd):
      stable_runs(t, E.Excerpt.group(ys), hk, hd)

def Laws.merge_stable(xs, t):
  +all = List.concat(&2, E.Ex, xs)
  +ss = E.Excerpt.sort(all)
  %sort_only(t, all)
    : {D2.recs(D2.only(t, E.Excerpt.joined(E.Excerpt.group(ss))))
      == D2.recs(Laws.firsts(_, [])) : List<&2, R.Record>}
  %group_flat(ss)
    : {D2.recs(D2.only(t, E.Excerpt.joined(E.Excerpt.group(ss))))
      == D2.recs(Laws.firsts(D2.only(t, _), [])) : List<&2, R.Record>}
  stable_runs.ok(t, ss, group_ok(ss, sort_rising(all)))
