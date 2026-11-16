# proofs of laws/RecordsInputChanges.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/live.bend as L
import ../src/intake.bend as I
import ../laws/RecordsInputChanges.bend as Laws
import ../laws/LiveKeepsLastVersion.bend as LK
import ../laws/defs/CurrentRecords.bend as D2
import ../laws/defs/InputRecords.bend as D1
import ./lemmas/CurrentFacts.bend as M1
import ./lemmas/PackingSteps.bend as M2

def Laws.input_same(held, x, h, e, s):
  %Equal.sym(Maybe<&2, R.Record>, L.Live.pick(L.Live.id(x), held), Some{h}, e)
    : {I.Intake.vs(_, x, []) == [] : List<&2, R.Record>}
  %Equal.sym(Bool, I.Intake.same(h, x), True{}, s)
    : {I.Intake.changed(_, x, []) == [] : List<&2, R.Record>}
  {==}

def Laws.input_new(held, x, e):
  %Equal.sym(Maybe<&2, R.Record>, L.Live.pick(L.Live.id(x), held), None{}, e)
    : {I.Intake.vs(_, x, []) == [x] : List<&2, R.Record>}
  {==}

def Laws.input_changed(held, x, h, e, s):
  %Equal.sym(Maybe<&2, R.Record>, L.Live.pick(L.Live.id(x), held), Some{h}, e)
    : {I.Intake.vs(_, x, []) == [I.Intake.removal(x), x] : List<&2, R.Record>}
  %Equal.sym(Bool, I.Intake.same(h, x), False{}, s)
    : {I.Intake.changed(_, x, []) == [I.Intake.removal(x), x] : List<&2, R.Record>}
  {==}

# appending regroups
law app_assoc:
  for a: List<&2, R.Record>
  for +b: List<&2, R.Record>
  for +c: List<&2, R.Record>
  {List.append(&2, R.Record, List.append(&2, R.Record, a, b), c)
    == List.append(&2, R.Record, a, List.append(&2, R.Record, b, c)) : List<&2, R.Record>}

def app_assoc(a, b, c):
  match a:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      Equal.cong(List<&2, R.Record>, List<&2, R.Record>, l => x <> l,
        List.append(&2, R.Record, List.append(&2, R.Record, rest, b), c),
        List.append(&2, R.Record, rest, List.append(&2, R.Record, b, c)), app_assoc(rest, b, c))

# the first with the id past a record kept or not, when it is known whether
# the record has the id (b)
law without_step:
  for b: Bool
  for +i: String
  for +z: R.Record
  for +r: List<&2, R.Record>
  for +m: List<&2, R.Record>
  for eb: {String.eq(i, L.Live.id(z)) == b : Bool}
  for ih: {D2.first(i, List.append(&2, R.Record, D2.without(i, r), m)) == D2.first(i, m)
    : Maybe<&2, R.Record>}
  {D2.first(i, List.append(&2, R.Record, D2.without.if(b, z, D2.without(i, r)), m))
    == D2.first(i, m) : Maybe<&2, R.Record>}

def without_step(b, i, z, r, m, eb, ih):
  match b:
    case True{}:
      ih
    case False{}:
      %Equal.sym(Bool, String.eq(L.Live.id(z), i), False{}, M1.eq_sym_false(L.Live.id(z), i, eb))
        : {D2.first.if(_, z, D2.first(i, List.append(&2, R.Record, D2.without(i, r), m)))
          == D2.first(i, m) : Maybe<&2, R.Record>}
      ih

# records without the id add no first with it
law first_without:
  for +i: String
  for l: List<&2, R.Record>
  for +m: List<&2, R.Record>
  {D2.first(i, List.append(&2, R.Record, D2.without(i, l), m)) == D2.first(i, m)
    : Maybe<&2, R.Record>}

def first_without(i, l, m):
  match l:
    case Nil{}:
      {==}
    case Con{+z, +r}:
      without_step(String.eq(i, L.Live.id(z)), i, z, r, m, {==}, first_without(i, r, m))

def Laws.input_current(ys, x, g):
  +rx = I.Intake.removal(x)
  +zs = List.append(&2, R.Record, ys, [rx])
  Equal.trans(Maybe<&2, R.Record>,
    L.Live.find(L.Live.id(x), List.append(&2, R.Record, ys, [rx, x])),
    D2.first(L.Live.id(x), L.Live.of(List.append(&2, R.Record, zs, [x]))),
    Some{x},
    (%Equal.sym(List<&2, R.Record>, List.append(&2, R.Record, zs, [x]),
        List.append(&2, R.Record, ys, [rx, x]), app_assoc(ys, [rx], [x]))
      : {L.Live.find(L.Live.id(x), List.append(&2, R.Record, ys, [rx, x]))
        == D2.first(L.Live.id(x), L.Live.of(_)) : Maybe<&2, R.Record>};
      LK.find_live(L.Live.id(x), List.append(&2, R.Record, ys, [rx, x]))),
    (%Equal.sym(List<&2, R.Record>, L.Live.of(List.append(&2, R.Record, zs, [x])),
        List.append(&2, R.Record, D2.without(L.Live.id(x), L.Live.of(zs)), D2.alone(x)),
        LK.live_last(zs, x))
      : {D2.first(L.Live.id(x), _) == Some{x} : Maybe<&2, R.Record>};
      Equal.trans(Maybe<&2, R.Record>,
        D2.first(L.Live.id(x), List.append(&2, R.Record, D2.without(L.Live.id(x), L.Live.of(zs)), D2.alone(x))),
        D2.first(L.Live.id(x), D2.alone(x)), Some{x},
        first_without(L.Live.id(x), L.Live.of(zs), D2.alone(x)),
        (%Equal.sym(Bool, L.Live.gone(x), False{}, g)
          : {D2.first(L.Live.id(x), D2.alone.if(_, x)) == Some{x} : Maybe<&2, R.Record>};
          %Equal.sym(Bool, String.eq(L.Live.id(x), L.Live.id(x)), True{}, M2.eq_refl(L.Live.id(x)))
            : {D2.first.if(_, x, None{}) == Some{x} : Maybe<&2, R.Record>};
          {==}))))

def Laws.removal_clears(ys, x):
  match x:
    case R.Record{+id, +ts, +source, _author, _thread, _parent, _paras, _ptr}:
      +rx = {R.Record{id, ts, source, "", "", "", [P.Para{1, 0, 0, "(removed)"}], L.Live.removed()} : R.Record}
      Equal.trans(Maybe<&2, R.Record>,
        L.Live.find(id, List.append(&2, R.Record, ys, [rx])),
        D2.first(id, L.Live.of(List.append(&2, R.Record, ys, [rx]))),
        None{},
        LK.find_live(id, List.append(&2, R.Record, ys, [rx])),
        (%Equal.sym(List<&2, R.Record>, L.Live.of(List.append(&2, R.Record, ys, [rx])),
            List.append(&2, R.Record, D2.without(id, L.Live.of(ys)), D2.alone(rx)),
            LK.live_last(ys, rx))
          : {D2.first(id, _) == None{} : Maybe<&2, R.Record>};
          first_without(id, L.Live.of(ys), [])))

# a changed record and its removal, or nothing, keep an id missing
def ch_frame(
  b: Bool,
  x: R.Record,
  +rest: List<&2, R.Record>,
  +i: String,
  ex: {String.eq(L.Live.id(x), i) == False{} : Bool},
  er: {L.Live.has(i, rest) == False{} : Bool}
) -> {L.Live.has(i, I.Intake.changed(b, x, rest)) == False{} : Bool}:
  match b:
    case True{}:
      er
    case False{}:
      match x:
        case R.Record{+id, ts, source, author, thread, parent, paras, ptr}:
          %Equal.sym(Bool, String.eq(id, i), False{}, ex)
            : {Bool.or(_, Bool.or(_, L.Live.has(i, rest))) == False{} : Bool}
          er

# what a record gives keeps an id it lacks missing
def vs_frame(
  cur: Maybe<&2, R.Record>,
  +x: R.Record,
  +rest: List<&2, R.Record>,
  +i: String,
  +ex: {String.eq(L.Live.id(x), i) == False{} : Bool},
  er: {L.Live.has(i, rest) == False{} : Bool}
) -> {L.Live.has(i, I.Intake.vs(cur, x, rest)) == False{} : Bool}:
  match cur:
    case None{}:
      %Equal.sym(Bool, String.eq(L.Live.id(x), i), False{}, ex)
        : {Bool.or(_, L.Live.has(i, rest)) == False{} : Bool}
      er
    case Some{h}:
      ch_frame(I.Intake.same(h, x), x, rest, i, ex, er)

def Laws.input_frame(i, held, xs, h):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      vs_frame(L.Live.pick(L.Live.id(x), held), x, I.Intake.ones(held, rest), i,
        M1.or_fl(String.eq(L.Live.id(x), i), L.Live.has(i, rest), h),
        Laws.input_frame(i, held, rest, M1.or_fr(String.eq(L.Live.id(x), i), L.Live.has(i, rest), h)))

# a removal kept or not, against the specification's
def lacks_step(
  b: Bool,
  +h: R.Record,
  -l: List<&2, R.Record>,
  -m: List<&2, R.Record>,
  ih: {l == D1.removals(m) : List<&2, R.Record>}
) -> {I.Intake.lacks.if(b, h, l) == D1.removals(D1.lacking.if(b, h, m)) : List<&2, R.Record>}:
  match b:
    case True{}:
      Equal.cong(List<&2, R.Record>, List<&2, R.Record>, z => I.Intake.removal(h) <> z, l,
        D1.removals(m), ih)
    case False{}:
      ih

# the removals a complete run appends are the specification's
law lacks_spec:
  for held: List<&2, R.Record>
  for +xs: List<&2, R.Record>
  {I.Intake.lacks(held, xs) == D1.removals(D1.lacking(held, xs)) : List<&2, R.Record>}

def lacks_spec(held, xs):
  match held:
    case Nil{}:
      {==}
    case Con{+h, +rest}:
      lacks_step(Bool.not(L.Live.has(L.Live.id(h), xs)), h, I.Intake.lacks(rest, xs),
        D1.lacking(rest, xs), lacks_spec(rest, xs))

def Laws.complete_lacking(held, xs):
  Equal.cong(List<&2, R.Record>, List<&2, R.Record>,
    z => List.append(&2, R.Record, I.Intake.ones(held, xs), z),
    I.Intake.lacks(held, xs), D1.removals(D1.lacking(held, xs)), lacks_spec(held, xs))
