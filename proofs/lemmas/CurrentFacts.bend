# facts about current records: or, the ids a list of records has, and a
# record kept or not by Live.put
import Base
import ../../src/record.bend as R
import ../../src/live.bend as L
import ./BoolFacts.bend as M1
import ./PackingSteps.bend as M2
import ./TextOrder.bend as M3

# an or with a false right side is its left side
def or_f(a: Bool) -> {Bool.or(a, False{}) == a : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# or regroups
def or_assoc(a: Bool, -b: Bool, -c: Bool) -> {Bool.or(Bool.or(a, b), c) == Bool.or(a, Bool.or(b, c)) : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# a false or has a false left side
def or_fl(a: Bool, -b: Bool, e: {Bool.or(a, b) == False{} : Bool}) -> {a == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      e

# a false or has a false right side
def or_fr(a: Bool, -b: Bool, e: {Bool.or(a, b) == False{} : Bool}) -> {b == False{} : Bool}:
  match a:
    case False{}:
      e
    case True{}:
      Empty.absurd({b == False{} : Bool}, M1.clash(Equal.sym(Bool, True{}, False{}, e)))

# a true not is of false
def not_t(a: Bool, e: {Bool.not(a) == True{} : Bool}) -> {a == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({True{} == False{} : Bool}, M1.clash(e))

# the ids of a ++ b are those of a, then those of b
law has_app:
  for +i: String
  for a: List<&2, R.Record>
  for +b: List<&2, R.Record>
  {L.Live.has(i, List.append(&2, R.Record, a, b))
    == Bool.or(L.Live.has(i, a), L.Live.has(i, b)) : Bool}

def has_app(i, a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+x, +r}:
      %Equal.sym(Bool,
        Bool.or(Bool.or(String.eq(L.Live.id(x), i), L.Live.has(i, r)), L.Live.has(i, b)),
        Bool.or(String.eq(L.Live.id(x), i), Bool.or(L.Live.has(i, r), L.Live.has(i, b))),
        or_assoc(String.eq(L.Live.id(x), i), L.Live.has(i, r), L.Live.has(i, b)))
        : {Bool.or(String.eq(L.Live.id(x), i), L.Live.has(i, List.append(&2, R.Record, r, b)))
          == _ : Bool}
      %has_app(i, r, b)
        : {Bool.or(String.eq(L.Live.id(x), i), L.Live.has(i, List.append(&2, R.Record, r, b)))
          == Bool.or(String.eq(L.Live.id(x), i), _) : Bool}
      {==}

# a record kept or not leaves an id missing when the record and the rest
# lack it
def has_put(
  +i: String,
  a: Bool,
  g: Bool,
  +x: R.Record,
  -m: List<&2, R.Record>,
  ex: {String.eq(L.Live.id(x), i) == False{} : Bool},
  em: {L.Live.has(i, m) == False{} : Bool}
) -> {L.Live.has(i, L.Live.put(a, g, x, m)) == False{} : Bool}:
  match a:
    case True{}:
      em
    case False{}:
      match g:
        case True{}:
          em
        case False{}:
          %Equal.sym(Bool, String.eq(L.Live.id(x), i), False{}, ex)
            : {Bool.or(_, L.Live.has(i, m)) == False{} : Bool}
          em

# an id no record of r has, no current record of r has
law has_live:
  for +i: String
  for r: List<&2, R.Record>
  for +e: {L.Live.has(i, r) == False{} : Bool}
  {L.Live.has(i, L.Live.of(r)) == False{} : Bool}

def has_live(i, r, e):
  match r:
    case Nil{}:
      {==}
    case Con{+y, +t}:
      has_put(i, L.Live.has(L.Live.id(y), t), L.Live.gone(y), y, L.Live.of(t),
        or_fl(String.eq(L.Live.id(y), i), L.Live.has(i, t), e),
        has_live(i, t, or_fr(String.eq(L.Live.id(y), i), L.Live.has(i, t), e)))

# appending after a record kept or not is appending after the rest
def put_app(
  a: Bool,
  g: Bool,
  -x: R.Record,
  -m: List<&2, R.Record>,
  -n: List<&2, R.Record>
) -> {List.append(&2, R.Record, L.Live.put(a, g, x, m), n)
  == L.Live.put(a, g, x, List.append(&2, R.Record, m, n)) : List<&2, R.Record>}:
  match a:
    case True{}:
      {==}
    case False{}:
      match g:
        case True{}:
          {==}
        case False{}:
          {==}

# a removal is never kept
def put_gone(
  a: Bool,
  -x: R.Record,
  -m: List<&2, R.Record>
) -> {L.Live.put(a, True{}, x, m) == m : List<&2, R.Record>}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# eq_sym_false once String.eq(a, b) is known to be c
def eq_sym_false.go(
  c: Bool,
  +a: String,
  +b: String,
  ec: {String.eq(a, b) == c : Bool},
  e: {String.eq(b, a) == False{} : Bool}
) -> {c == False{} : Bool}:
  match c:
    case False{}:
      {==}
    case True{}:
      Equal.trans(Bool, True{}, String.eq(b, a), False{},
        (%Equal.sym(String, a, b, M3.order_eq(a, b, EQ{}, ec))
          : {True{} == String.eq(b, _) : Bool};
          Equal.sym(Bool, String.eq(b, b), True{}, M2.eq_refl(b))),
        e)

# a text unequal to another, the other is unequal to it
def eq_sym_false(
  +a: String,
  +b: String,
  e: {String.eq(b, a) == False{} : Bool}
) -> {String.eq(a, b) == False{} : Bool}:
  eq_sym_false.go(String.eq(a, b), a, b, {==}, e)

# an or with a true right side is true
def or_t(a: Bool, -b: Bool, e: {b == True{} : Bool}) -> {Bool.or(a, b) == True{} : Bool}:
  match a:
    case False{}:
      e
    case True{}:
      {==}
