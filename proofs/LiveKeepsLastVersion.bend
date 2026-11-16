# proofs of laws/LiveKeepsLastVersion.bend
import Base
import ../src/record.bend as R
import ../src/live.bend as L
import ../laws/LiveKeepsLastVersion.bend as Laws
import ../laws/defs/CurrentRecords.bend as D1
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/CurrentFacts.bend as M2
import ./lemmas/TextOrder.bend as M3

# --- live_last ---

# one record alone is current unless it is a removal
def last_nil(g: Bool, -x: R.Record) -> {L.Live.put(False{}, g, x, []) == D1.alone.if(g, x) : List<&2, R.Record>}:
  match g:
    case True{}:
      {==}
    case False{}:
      {==}

# the step of live_last once the later ids are known: h whether r has y's
# id, g whether y is a removal, e whether x has y's id
def last_step(
  h: Bool,
  g: Bool,
  e: Bool,
  +y: R.Record,
  +x: R.Record,
  +m: List<&2, R.Record>,
  +lr: List<&2, R.Record>,
  ee: {String.eq(L.Live.id(x), L.Live.id(y)) == e : Bool},
  ih: {m == List.append(&2, R.Record, D1.without(L.Live.id(x), lr), D1.alone(x)) : List<&2, R.Record>}
) -> {L.Live.put(Bool.or(h, e), g, y, m)
  == List.append(&2, R.Record,
    D1.without(L.Live.id(x), L.Live.put(h, g, y, lr)), D1.alone(x)) : List<&2, R.Record>}:
  match h:
    case True{}:
      ih
    case False{}:
      match g:
        case True{}:
          %Equal.sym(List<&2, R.Record>, L.Live.put(e, True{}, y, m), m, M2.put_gone(e, y, m))
            : {_ == List.append(&2, R.Record, D1.without(L.Live.id(x), lr), D1.alone(x))
              : List<&2, R.Record>}
          ih
        case False{}:
          match e:
            case True{}:
              %Equal.sym(Bool, String.eq(L.Live.id(x), L.Live.id(y)), True{}, ee)
                : {m == List.append(&2, R.Record, D1.without.if(_, y, D1.without(L.Live.id(x), lr)),
                  D1.alone(x)) : List<&2, R.Record>}
              ih
            case False{}:
              %Equal.sym(Bool, String.eq(L.Live.id(x), L.Live.id(y)), False{}, ee)
                : {y <> m == List.append(&2, R.Record, D1.without.if(_, y, D1.without(L.Live.id(x), lr)),
                  D1.alone(x)) : List<&2, R.Record>}
              Equal.cong(List<&2, R.Record>, List<&2, R.Record>, l => y <> l, m,
                List.append(&2, R.Record, D1.without(L.Live.id(x), lr), D1.alone(x)), ih)

# whether a record has y's id is whether the records before have it or x
# has it
law has_snoc:
  for +i: String
  for r: List<&2, R.Record>
  for +x: R.Record
  {L.Live.has(i, List.append(&2, R.Record, r, [x]))
    == Bool.or(L.Live.has(i, r), String.eq(L.Live.id(x), i)) : Bool}

def has_snoc(i, r, x):
  %M2.or_f(String.eq(L.Live.id(x), i))
    : {L.Live.has(i, List.append(&2, R.Record, r, [x])) == Bool.or(L.Live.has(i, r), _) : Bool}
  M2.has_app(i, r, [x])

def Laws.live_last(xs, x):
  match xs:
    case Nil{}:
      last_nil(L.Live.gone(x), x)
    case Con{+y, +r}:
      %Equal.sym(Bool, L.Live.has(L.Live.id(y), List.append(&2, R.Record, r, [x])),
        Bool.or(L.Live.has(L.Live.id(y), r), String.eq(L.Live.id(x), L.Live.id(y))),
        has_snoc(L.Live.id(y), r, x))
        : {L.Live.put(_, L.Live.gone(y), y, L.Live.of(List.append(&2, R.Record, r, [x])))
          == List.append(&2, R.Record,
            D1.without(L.Live.id(x), L.Live.put(L.Live.has(L.Live.id(y), r), L.Live.gone(y), y,
              L.Live.of(r))), D1.alone(x)) : List<&2, R.Record>}
      last_step(L.Live.has(L.Live.id(y), r), L.Live.gone(y), String.eq(L.Live.id(x), L.Live.id(y)),
        y, x, L.Live.of(List.append(&2, R.Record, r, [x])), L.Live.of(r), {==},
        Laws.live_last(r, x))

# --- live_append ---

# the step of live_append once it is known whether the rest has x's id (h)
# and whether x is a removal (g)
law app_step:
  for h: Bool
  for g: Bool
  for +x: R.Record
  for +rest: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for eh: {L.Live.has(L.Live.id(x), rest) == h : Bool}
  for eg: {L.Live.gone(x) == g : Bool}
  for ih: {L.Live.of(List.append(&2, R.Record, L.Live.of(rest), ys))
    == L.Live.of(List.append(&2, R.Record, rest, ys)) : List<&2, R.Record>}
  {L.Live.of(List.append(&2, R.Record, L.Live.put(h, g, x, L.Live.of(rest)), ys))
    == L.Live.put(Bool.or(h, L.Live.has(L.Live.id(x), ys)), g, x,
      L.Live.of(List.append(&2, R.Record, rest, ys))) : List<&2, R.Record>}

def app_step(h, g, x, rest, ys, eh, eg, ih):
  match h:
    case True{}:
      ih
    case False{}:
      match g:
        case True{}:
          %Equal.sym(List<&2, R.Record>,
            L.Live.put(L.Live.has(L.Live.id(x), ys), True{}, x,
              L.Live.of(List.append(&2, R.Record, rest, ys))),
            L.Live.of(List.append(&2, R.Record, rest, ys)),
            M2.put_gone(L.Live.has(L.Live.id(x), ys), x,
              L.Live.of(List.append(&2, R.Record, rest, ys))))
            : {L.Live.of(List.append(&2, R.Record, L.Live.of(rest), ys)) == _
              : List<&2, R.Record>}
          ih
        case False{}:
          %Equal.sym(Bool, L.Live.gone(x), False{}, eg)
            : {L.Live.put(L.Live.has(L.Live.id(x), List.append(&2, R.Record, L.Live.of(rest), ys)),
                _, x, L.Live.of(List.append(&2, R.Record, L.Live.of(rest), ys)))
              == L.Live.put(L.Live.has(L.Live.id(x), ys), False{}, x,
                L.Live.of(List.append(&2, R.Record, rest, ys))) : List<&2, R.Record>}
          %Equal.sym(Bool,
            L.Live.has(L.Live.id(x), List.append(&2, R.Record, L.Live.of(rest), ys)),
            Bool.or(L.Live.has(L.Live.id(x), L.Live.of(rest)), L.Live.has(L.Live.id(x), ys)),
            M2.has_app(L.Live.id(x), L.Live.of(rest), ys))
            : {L.Live.put(_, False{}, x, L.Live.of(List.append(&2, R.Record, L.Live.of(rest), ys)))
              == L.Live.put(L.Live.has(L.Live.id(x), ys), False{}, x,
                L.Live.of(List.append(&2, R.Record, rest, ys))) : List<&2, R.Record>}
          %Equal.sym(Bool, L.Live.has(L.Live.id(x), L.Live.of(rest)), False{},
            M2.has_live(L.Live.id(x), rest, eh))
            : {L.Live.put(Bool.or(_, L.Live.has(L.Live.id(x), ys)), False{}, x,
                L.Live.of(List.append(&2, R.Record, L.Live.of(rest), ys)))
              == L.Live.put(L.Live.has(L.Live.id(x), ys), False{}, x,
                L.Live.of(List.append(&2, R.Record, rest, ys))) : List<&2, R.Record>}
          %ih
            : {L.Live.put(L.Live.has(L.Live.id(x), ys), False{}, x,
                L.Live.of(List.append(&2, R.Record, L.Live.of(rest), ys)))
              == L.Live.put(L.Live.has(L.Live.id(x), ys), False{}, x, _) : List<&2, R.Record>}
          {==}

def Laws.live_append(xs, ys):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(Bool, L.Live.has(L.Live.id(x), List.append(&2, R.Record, rest, ys)),
        Bool.or(L.Live.has(L.Live.id(x), rest), L.Live.has(L.Live.id(x), ys)),
        M2.has_app(L.Live.id(x), rest, ys))
        : {L.Live.of(List.append(&2, R.Record,
            L.Live.put(L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, L.Live.of(rest)), ys))
          == L.Live.put(_, L.Live.gone(x), x, L.Live.of(List.append(&2, R.Record, rest, ys)))
          : List<&2, R.Record>}
      app_step(L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, rest, ys, {==}, {==},
        Laws.live_append(rest, ys))

# --- live_fresh ---

def Laws.live_fresh(xs, ys, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      +lr = L.Live.of(rest)
      +ly = L.Live.of(ys)
      +hx = L.Live.has(L.Live.id(x), rest)
      +hy = L.Live.has(L.Live.id(x), ys)
      %Equal.sym(Bool, L.Live.has(L.Live.id(x), List.append(&2, R.Record, rest, ys)),
        Bool.or(hx, hy), M2.has_app(L.Live.id(x), rest, ys))
        : {L.Live.put(_, L.Live.gone(x), x, L.Live.of(List.append(&2, R.Record, rest, ys)))
          == List.append(&2, R.Record, L.Live.put(hx, L.Live.gone(x), x, lr), ly)
          : List<&2, R.Record>}
      %Equal.sym(Bool, hy, False{},
        M2.not_t(hy, M1.and_l(Bool.not(hy), D1.fresh(rest, ys), h)))
        : {L.Live.put(Bool.or(hx, _), L.Live.gone(x), x,
            L.Live.of(List.append(&2, R.Record, rest, ys)))
          == List.append(&2, R.Record, L.Live.put(hx, L.Live.gone(x), x, lr), ly)
          : List<&2, R.Record>}
      %Equal.sym(Bool, Bool.or(hx, False{}), hx, M2.or_f(hx))
        : {L.Live.put(_, L.Live.gone(x), x, L.Live.of(List.append(&2, R.Record, rest, ys)))
          == List.append(&2, R.Record, L.Live.put(hx, L.Live.gone(x), x, lr), ly)
          : List<&2, R.Record>}
      %Equal.sym(List<&2, R.Record>,
        List.append(&2, R.Record, L.Live.put(hx, L.Live.gone(x), x, lr), ly),
        L.Live.put(hx, L.Live.gone(x), x, List.append(&2, R.Record, lr, ly)),
        M2.put_app(hx, L.Live.gone(x), x, lr, ly))
        : {L.Live.put(hx, L.Live.gone(x), x, L.Live.of(List.append(&2, R.Record, rest, ys)))
          == _ : List<&2, R.Record>}
      %Laws.live_fresh(rest, ys, M1.and_r(Bool.not(hy), D1.fresh(rest, ys), h))
        : {L.Live.put(hx, L.Live.gone(x), x, L.Live.of(List.append(&2, R.Record, rest, ys)))
          == L.Live.put(hx, L.Live.gone(x), x, _) : List<&2, R.Record>}
      {==}

# --- find_live ---

# a record kept or not that lacks the id leaves the first with it alone
def first_put_miss(
  a: Bool,
  g: Bool,
  +i: String,
  +y: R.Record,
  +m: List<&2, R.Record>,
  e: {String.eq(L.Live.id(y), i) == False{} : Bool}
) -> {D1.first(i, L.Live.put(a, g, y, m)) == D1.first(i, m) : Maybe<&2, R.Record>}:
  match a:
    case True{}:
      {==}
    case False{}:
      match g:
        case True{}:
          {==}
        case False{}:
          %Equal.sym(Bool, String.eq(L.Live.id(y), i), False{}, e)
            : {D1.first.if(_, y, D1.first(i, m)) == D1.first(i, m) : Maybe<&2, R.Record>}
          {==}

# an id no record of r has, no current record of r has first
law first_none:
  for +i: String
  for r: List<&2, R.Record>
  for +e: {L.Live.has(i, r) == False{} : Bool}
  {D1.first(i, L.Live.of(r)) == None{} : Maybe<&2, R.Record>}

def first_none(i, r, e):
  match r:
    case Nil{}:
      {==}
    case Con{+y, +t}:
      Equal.trans(Maybe<&2, R.Record>,
        D1.first(i, L.Live.put(L.Live.has(L.Live.id(y), t), L.Live.gone(y), y, L.Live.of(t))),
        D1.first(i, L.Live.of(t)), None{},
        first_put_miss(L.Live.has(L.Live.id(y), t), L.Live.gone(y), i, y, L.Live.of(t),
          M2.or_fl(String.eq(L.Live.id(y), i), L.Live.has(i, t), e)),
        first_none(i, t, M2.or_fr(String.eq(L.Live.id(y), i), L.Live.has(i, t), e)))

# the step of find_live once it is known whether x has the id (e), whether
# the rest has x's id (h) and whether x is a removal (g)
def find_step(
  e: Bool,
  h: Bool,
  g: Bool,
  +id: String,
  +x: R.Record,
  +rest: List<&2, R.Record>,
  +ee: {String.eq(L.Live.id(x), id) == e : Bool},
  eh: {L.Live.has(L.Live.id(x), rest) == h : Bool},
  ih: {L.Live.find(id, rest) == D1.first(id, L.Live.of(rest)) : Maybe<&2, R.Record>}
) -> {L.Live.found.at(e, _u => h, g, x, L.Live.find(id, rest))
  == D1.first(id, L.Live.put(h, g, x, L.Live.of(rest))) : Maybe<&2, R.Record>}:
  match e:
    case False{}:
      Equal.trans(Maybe<&2, R.Record>, L.Live.find(id, rest), D1.first(id, L.Live.of(rest)),
        D1.first(id, L.Live.put(h, g, x, L.Live.of(rest))), ih,
        Equal.sym(Maybe<&2, R.Record>, D1.first(id, L.Live.put(h, g, x, L.Live.of(rest))),
          D1.first(id, L.Live.of(rest)),
          first_put_miss(h, g, id, x, L.Live.of(rest), ee)))
    case True{}:
      match h:
        case True{}:
          ih
        case False{}:
          match g:
            case True{}:
              %M3.order_eq(L.Live.id(x), id, EQ{}, ee)
                : {None{} == D1.first(_, L.Live.of(rest)) : Maybe<&2, R.Record>}
              Equal.sym(Maybe<&2, R.Record>, D1.first(L.Live.id(x), L.Live.of(rest)), None{},
                first_none(L.Live.id(x), rest, eh))
            case False{}:
              %Equal.sym(Bool, String.eq(L.Live.id(x), id), True{}, ee)
                : {Some{x} == D1.first.if(_, x, D1.first(id, L.Live.of(rest)))
                  : Maybe<&2, R.Record>}
              {==}

def Laws.find_live(id, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      find_step(String.eq(L.Live.id(x), id), L.Live.has(L.Live.id(x), rest), L.Live.gone(x),
        id, x, rest, {==}, {==}, Laws.find_live(id, rest))
