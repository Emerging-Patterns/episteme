# proofs of laws/ChangedRecordKeepsItsPlace.bend
import Base
import ../src/record.bend as R
import ../src/live.bend as L
import ../laws/ChangedRecordKeepsItsPlace.bend as Laws
import ../laws/LiveKeepsLastVersion.bend as LK
import ../laws/defs/CurrentRecords.bend as D1
import ./LiveKeepsLastVersion.bend as P1
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/CurrentFacts.bend as M2
import ./lemmas/TextOrder.bend as M3
import ./lemmas/PackingSteps.bend as M4

# appending after a record decided is deciding it ahead of what is appended
def one_app(
  h: Bool,
  -r: R.Record,
  f: Maybe<&2, R.Record>,
  -m: List<&2, R.Record>,
  -n: List<&2, R.Record>
) -> {List.append(&2, R.Record, L.Live.kept.one(h, r, f, m), n)
  == L.Live.kept.one(h, r, f, List.append(&2, R.Record, m, n)) : List<&2, R.Record>}:
  match h:
    case False{}:
      {==}
    case True{}:
      match f:
        case None{}:
          {==}
        case Some{y}:
          {==}

def Laws.kept_each(a, b, ys):
  match a:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      +h = L.Live.has(L.Live.id(x), ys)
      +f = L.Live.find(L.Live.id(x), ys)
      %Equal.sym(List<&2, R.Record>, L.Live.kept(List.append(&2, R.Record, t, b), ys),
        List.append(&2, R.Record, L.Live.kept(t, ys), L.Live.kept(b, ys)), Laws.kept_each(t, b, ys))
        : {L.Live.kept.one(h, x, f, _)
          == List.append(&2, R.Record, L.Live.kept.one(h, x, f, L.Live.kept(t, ys)), L.Live.kept(b, ys))
          : List<&2, R.Record>}
      Equal.sym(List<&2, R.Record>,
        List.append(&2, R.Record, L.Live.kept.one(h, x, f, L.Live.kept(t, ys)), L.Live.kept(b, ys)),
        L.Live.kept.one(h, x, f, List.append(&2, R.Record, L.Live.kept(t, ys), L.Live.kept(b, ys))),
        one_app(h, x, f, L.Live.kept(t, ys), L.Live.kept(b, ys)))

def Laws.kept_unnamed(r, ys, h):
  %Equal.sym(Bool, L.Live.has(L.Live.id(r), ys), False{}, h)
    : {L.Live.kept.one(_, r, L.Live.find(L.Live.id(r), ys), []) == [r] : List<&2, R.Record>}
  {==}

# a named record alone is the batch's last version of its id, or nothing
def one_given(
  -r: R.Record,
  f: Maybe<&2, R.Record>
) -> {L.Live.kept.one(True{}, r, f, []) == D1.given(f) : List<&2, R.Record>}:
  match f:
    case None{}:
      {==}
    case Some{y}:
      {==}

def Laws.kept_named(r, ys, h):
  %Equal.sym(Bool, L.Live.has(L.Live.id(r), ys), True{}, h)
    : {L.Live.kept.one(_, r, L.Live.find(L.Live.id(r), ys), [])
      == D1.given(L.Live.find(L.Live.id(r), ys)) : List<&2, R.Record>}
  one_given(r, L.Live.find(L.Live.id(r), ys))

# --- next_new ---

# a list without an id none of its records has is the list
law less_miss:
  for +i: String
  for zs: List<&2, R.Record>
  for +e: {L.Live.has(i, zs) == False{} : Bool}
  {L.Live.less(i, zs) == zs : List<&2, R.Record>}

def less_miss(i, zs, e):
  match zs:
    case Nil{}:
      {==}
    case Con{+z, +t}:
      %Equal.sym(List<&2, R.Record>, L.Live.less(i, t), t,
        less_miss(i, t, M2.or_fr(String.eq(L.Live.id(z), i), L.Live.has(i, t), e)))
        : {L.Live.less.if(String.eq(L.Live.id(z), i), z, _) == z <> t : List<&2, R.Record>}
      %Equal.sym(Bool, String.eq(L.Live.id(z), i), False{},
        M2.or_fl(String.eq(L.Live.id(z), i), L.Live.has(i, t), e))
        : {L.Live.less.if(_, z, t) == z <> t : List<&2, R.Record>}
      {==}

# records none of whose ids m has are all added
law added_miss:
  for m: List<&2, R.Record>
  for +zs: List<&2, R.Record>
  for +h: {D1.fresh(m, zs) == True{} : Bool}
  {L.Live.added(m, zs) == zs : List<&2, R.Record>}

def added_miss(m, zs, h):
  match m:
    case Nil{}:
      {==}
    case Con{+r, +rest}:
      %Equal.sym(List<&2, R.Record>, L.Live.less(L.Live.id(r), zs), zs,
        less_miss(L.Live.id(r), zs, M2.not_t(L.Live.has(L.Live.id(r), zs),
          M1.and_l(Bool.not(L.Live.has(L.Live.id(r), zs)), D1.fresh(rest, zs), h))))
        : {L.Live.added(rest, _) == zs : List<&2, R.Record>}
      added_miss(rest, zs, M1.and_r(Bool.not(L.Live.has(L.Live.id(r), zs)), D1.fresh(rest, zs), h))

# records none of whose ids the batch names are all kept as they are
law kept_miss:
  for m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +h: {D1.fresh(m, ys) == True{} : Bool}
  {L.Live.kept(m, ys) == m : List<&2, R.Record>}

def kept_miss(m, ys, h):
  match m:
    case Nil{}:
      {==}
    case Con{+r, +rest}:
      %Equal.sym(List<&2, R.Record>, L.Live.kept(rest, ys), rest,
        kept_miss(rest, ys, M1.and_r(Bool.not(L.Live.has(L.Live.id(r), ys)), D1.fresh(rest, ys), h)))
        : {L.Live.kept.one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), _)
          == r <> rest : List<&2, R.Record>}
      %Equal.sym(Bool, L.Live.has(L.Live.id(r), ys), False{},
        M2.not_t(L.Live.has(L.Live.id(r), ys),
          M1.and_l(Bool.not(L.Live.has(L.Live.id(r), ys)), D1.fresh(rest, ys), h)))
        : {L.Live.kept.one(_, r, L.Live.find(L.Live.id(r), ys), rest) == r <> rest : List<&2, R.Record>}
      {==}

# records with no id of a batch have no id of its current records
law fresh_live:
  for m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +h: {D1.fresh(m, ys) == True{} : Bool}
  {D1.fresh(m, L.Live.of(ys)) == True{} : Bool}

def fresh_live(m, ys, h):
  match m:
    case Nil{}:
      {==}
    case Con{+r, +rest}:
      %Equal.sym(Bool, L.Live.has(L.Live.id(r), L.Live.of(ys)), False{},
        M2.has_live(L.Live.id(r), ys, M2.not_t(L.Live.has(L.Live.id(r), ys),
          M1.and_l(Bool.not(L.Live.has(L.Live.id(r), ys)), D1.fresh(rest, ys), h))))
        : {Bool.and(Bool.not(_), D1.fresh(rest, L.Live.of(ys))) == True{} : Bool}
      fresh_live(rest, ys, M1.and_r(Bool.not(L.Live.has(L.Live.id(r), ys)), D1.fresh(rest, ys), h))

def Laws.next_new(m, ys, h):
  %Equal.sym(List<&2, R.Record>, L.Live.kept(m, ys), m, kept_miss(m, ys, h))
    : {List.append(&2, R.Record, _, L.Live.added(m, L.Live.of(ys)))
      == List.append(&2, R.Record, m, L.Live.of(ys)) : List<&2, R.Record>}
  %Equal.sym(List<&2, R.Record>, L.Live.added(m, L.Live.of(ys)), L.Live.of(ys),
    added_miss(m, L.Live.of(ys), fresh_live(m, ys, h)))
    : {List.append(&2, R.Record, m, _) == List.append(&2, R.Record, m, L.Live.of(ys)) : List<&2, R.Record>}
  {==}

# --- a batch's last version of an id has the id ---

# True when the record given has the id, and when none is given
def named(+j: String, rec: Maybe<&2, R.Record>) -> Bool:
  match rec:
    case None{}:
      True{}
    case Some{y}:
      String.eq(L.Live.id(y), j)

# the step of find_named once it is known whether x has the id (e)
def named_step(
  e: Bool,
  h: Bool,
  g: Bool,
  +j: String,
  +x: R.Record,
  -nx: Maybe<&2, R.Record>,
  ee: {String.eq(L.Live.id(x), j) == e : Bool},
  ih: {named(j, nx) == True{} : Bool}
) -> {named(j, L.Live.found.at(e, _u => h, g, x, nx)) == True{} : Bool}:
  match e:
    case False{}:
      ih
    case True{}:
      match h:
        case True{}:
          ih
        case False{}:
          match g:
            case True{}:
              {==}
            case False{}:
              ee

# the record a find gives has the id it was asked for
law find_named:
  for +j: String
  for ys: List<&2, R.Record>
  {named(j, L.Live.find(j, ys)) == True{} : Bool}

def find_named(j, ys):
  match ys:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      named_step(String.eq(L.Live.id(x), j), L.Live.has(L.Live.id(x), rest), L.Live.gone(x),
        j, x, L.Live.find(j, rest), {==}, find_named(j, rest))

# --- next_distinct ---

# a record decided ahead of records that lack an id lacks it too, when the
# record does and its last version has the record's id
def has_one(
  +i: String,
  h: Bool,
  +r: R.Record,
  f: Maybe<&2, R.Record>,
  -t: List<&2, R.Record>,
  e: {String.eq(L.Live.id(r), i) == False{} : Bool},
  nf: {named(L.Live.id(r), f) == True{} : Bool},
  et: {L.Live.has(i, t) == False{} : Bool}
) -> {L.Live.has(i, L.Live.kept.one(h, r, f, t)) == False{} : Bool}:
  match h:
    case False{}:
      %Equal.sym(Bool, String.eq(L.Live.id(r), i), False{}, e)
        : {Bool.or(_, L.Live.has(i, t)) == False{} : Bool}
      et
    case True{}:
      match f:
        case None{}:
          et
        case Some{+y}:
          %Equal.sym(String, L.Live.id(y), L.Live.id(r),
            M3.order_eq(L.Live.id(y), L.Live.id(r), EQ{}, nf))
            : {Bool.or(String.eq(_, i), L.Live.has(i, t)) == False{} : Bool}
          %Equal.sym(Bool, String.eq(L.Live.id(r), i), False{}, e)
            : {Bool.or(_, L.Live.has(i, t)) == False{} : Bool}
          et

# an id no record has, no record has after a batch
law has_kept:
  for +i: String
  for m: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +e: {L.Live.has(i, m) == False{} : Bool}
  {L.Live.has(i, L.Live.kept(m, ys)) == False{} : Bool}

def has_kept(i, m, ys, e):
  match m:
    case Nil{}:
      {==}
    case Con{+r, +rest}:
      has_one(i, L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), L.Live.kept(rest, ys),
        M2.or_fl(String.eq(L.Live.id(r), i), L.Live.has(i, rest), e),
        find_named(L.Live.id(r), ys),
        has_kept(i, rest, ys, M2.or_fr(String.eq(L.Live.id(r), i), L.Live.has(i, rest), e)))

# a record ahead or not of records that lack an id lacks it when the record does
def has_less_if(
  +i: String,
  hit: Bool,
  +z: R.Record,
  -t: List<&2, R.Record>,
  ez: {String.eq(L.Live.id(z), i) == False{} : Bool},
  et: {L.Live.has(i, t) == False{} : Bool}
) -> {L.Live.has(i, L.Live.less.if(hit, z, t)) == False{} : Bool}:
  match hit:
    case True{}:
      et
    case False{}:
      %Equal.sym(Bool, String.eq(L.Live.id(z), i), False{}, ez)
        : {Bool.or(_, L.Live.has(i, t)) == False{} : Bool}
      et

# an id no record has, no record has in the list without another id
law has_less:
  for +i: String
  for +j: String
  for zs: List<&2, R.Record>
  for +e: {L.Live.has(i, zs) == False{} : Bool}
  {L.Live.has(i, L.Live.less(j, zs)) == False{} : Bool}

def has_less(i, j, zs, e):
  match zs:
    case Nil{}:
      {==}
    case Con{+z, +t}:
      has_less_if(i, String.eq(L.Live.id(z), j), z, L.Live.less(j, t),
        M2.or_fl(String.eq(L.Live.id(z), i), L.Live.has(i, t), e),
        has_less(i, j, t, M2.or_fr(String.eq(L.Live.id(z), i), L.Live.has(i, t), e)))

# has_less_same once it is known whether z has the id (c)
def has_less_same.go(
  c: Bool,
  +i: String,
  +z: R.Record,
  -t: List<&2, R.Record>,
  ec: {String.eq(L.Live.id(z), i) == c : Bool},
  ih: {L.Live.has(i, t) == False{} : Bool}
) -> {L.Live.has(i, L.Live.less.if(c, z, t)) == False{} : Bool}:
  match c:
    case True{}:
      ih
    case False{}:
      %Equal.sym(Bool, String.eq(L.Live.id(z), i), False{}, ec)
        : {Bool.or(_, L.Live.has(i, t)) == False{} : Bool}
      ih

# no record of a list without an id has the id
law has_less_same:
  for +i: String
  for zs: List<&2, R.Record>
  {L.Live.has(i, L.Live.less(i, zs)) == False{} : Bool}

def has_less_same(i, zs):
  match zs:
    case Nil{}:
      {==}
    case Con{+z, +t}:
      has_less_same.go(String.eq(L.Live.id(z), i), i, z, L.Live.less(i, t), {==}, has_less_same(i, t))

# an id no record of zs has, none of those added has
law has_added:
  for +i: String
  for m: List<&2, R.Record>
  for +zs: List<&2, R.Record>
  for +e: {L.Live.has(i, zs) == False{} : Bool}
  {L.Live.has(i, L.Live.added(m, zs)) == False{} : Bool}

def has_added(i, m, zs, e):
  match m:
    case Nil{}:
      e
    case Con{+r, +rest}:
      has_added(i, rest, L.Live.less(L.Live.id(r), zs), has_less(i, L.Live.id(r), zs, e))

# a record ahead or not of distinct records that lack its id leaves them distinct
def distinct_less_if(
  hit: Bool,
  +z: R.Record,
  +t: List<&2, R.Record>,
  ez: {L.Live.has(L.Live.id(z), t) == False{} : Bool},
  dt: {D1.distinct(t) == True{} : Bool}
) -> {D1.distinct(L.Live.less.if(hit, z, t)) == True{} : Bool}:
  match hit:
    case True{}:
      dt
    case False{}:
      %Equal.sym(Bool, L.Live.has(L.Live.id(z), t), False{}, ez)
        : {Bool.and(Bool.not(_), D1.distinct(t)) == True{} : Bool}
      dt

# distinct records without an id are distinct
law distinct_less:
  for +j: String
  for zs: List<&2, R.Record>
  for +h: {D1.distinct(zs) == True{} : Bool}
  {D1.distinct(L.Live.less(j, zs)) == True{} : Bool}

def distinct_less(j, zs, h):
  match zs:
    case Nil{}:
      {==}
    case Con{+z, +t}:
      distinct_less_if(String.eq(L.Live.id(z), j), z, L.Live.less(j, t),
        has_less(L.Live.id(z), j, t, M2.not_t(L.Live.has(L.Live.id(z), t),
          M1.and_l(Bool.not(L.Live.has(L.Live.id(z), t)), D1.distinct(t), h))),
        distinct_less(j, t, M1.and_r(Bool.not(L.Live.has(L.Live.id(z), t)), D1.distinct(t), h)))

# a record kept or not keeps the current records distinct
def distinct_put(
  h: Bool,
  g: Bool,
  +x: R.Record,
  +rest: List<&2, R.Record>,
  eh: {L.Live.has(L.Live.id(x), rest) == h : Bool},
  ih: {D1.distinct(L.Live.of(rest)) == True{} : Bool}
) -> {D1.distinct(L.Live.put(h, g, x, L.Live.of(rest))) == True{} : Bool}:
  match h:
    case True{}:
      ih
    case False{}:
      match g:
        case True{}:
          ih
        case False{}:
          %Equal.sym(Bool, L.Live.has(L.Live.id(x), L.Live.of(rest)), False{},
            M2.has_live(L.Live.id(x), rest, eh))
            : {Bool.and(Bool.not(_), D1.distinct(L.Live.of(rest))) == True{} : Bool}
          ih

# no two current records of a batch have one id
law distinct_live:
  for ys: List<&2, R.Record>
  {D1.distinct(L.Live.of(ys)) == True{} : Bool}

def distinct_live(ys):
  match ys:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      distinct_put(L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, rest, {==}, distinct_live(rest))

# a record decided ahead of distinct records that lack its id leaves them
# distinct, its last version having its id
def distinct_one(
  h: Bool,
  +r: R.Record,
  f: Maybe<&2, R.Record>,
  +t: List<&2, R.Record>,
  nf: {named(L.Live.id(r), f) == True{} : Bool},
  et: {L.Live.has(L.Live.id(r), t) == False{} : Bool},
  dt: {D1.distinct(t) == True{} : Bool}
) -> {D1.distinct(L.Live.kept.one(h, r, f, t)) == True{} : Bool}:
  match h:
    case False{}:
      %Equal.sym(Bool, L.Live.has(L.Live.id(r), t), False{}, et)
        : {Bool.and(Bool.not(_), D1.distinct(t)) == True{} : Bool}
      dt
    case True{}:
      match f:
        case None{}:
          dt
        case Some{+y}:
          %Equal.sym(String, L.Live.id(y), L.Live.id(r),
            M3.order_eq(L.Live.id(y), L.Live.id(r), EQ{}, nf))
            : {Bool.and(Bool.not(L.Live.has(_, t)), D1.distinct(t)) == True{} : Bool}
          %Equal.sym(Bool, L.Live.has(L.Live.id(r), t), False{}, et)
            : {Bool.and(Bool.not(_), D1.distinct(t)) == True{} : Bool}
          dt

# distinct records after a batch, then distinct records m lacks, are distinct
law distinct_go:
  for m: List<&2, R.Record>
  for +zs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +hm: {D1.distinct(m) == True{} : Bool}
  for +hz: {D1.distinct(zs) == True{} : Bool}
  {D1.distinct(List.append(&2, R.Record, L.Live.kept(m, ys), L.Live.added(m, zs))) == True{} : Bool}

def distinct_go(m, zs, ys, hm, hz):
  match m:
    case Nil{}:
      hz
    case Con{+r, +rest}:
      +h = L.Live.has(L.Live.id(r), ys)
      +f = L.Live.find(L.Live.id(r), ys)
      +k = L.Live.kept(rest, ys)
      +a = L.Live.added(rest, L.Live.less(L.Live.id(r), zs))
      %Equal.sym(List<&2, R.Record>, List.append(&2, R.Record, L.Live.kept.one(h, r, f, k), a),
        L.Live.kept.one(h, r, f, List.append(&2, R.Record, k, a)), one_app(h, r, f, k, a))
        : {D1.distinct(_) == True{} : Bool}
      distinct_one(h, r, f, List.append(&2, R.Record, k, a), find_named(L.Live.id(r), ys),
        Equal.trans(Bool, L.Live.has(L.Live.id(r), List.append(&2, R.Record, k, a)),
          Bool.or(L.Live.has(L.Live.id(r), k), L.Live.has(L.Live.id(r), a)), False{},
          M2.has_app(L.Live.id(r), k, a),
          (%Equal.sym(Bool, L.Live.has(L.Live.id(r), k), False{},
            has_kept(L.Live.id(r), rest, ys, M2.not_t(L.Live.has(L.Live.id(r), rest),
              M1.and_l(Bool.not(L.Live.has(L.Live.id(r), rest)), D1.distinct(rest), hm))))
            : {Bool.or(_, L.Live.has(L.Live.id(r), a)) == False{} : Bool};
            has_added(L.Live.id(r), rest, L.Live.less(L.Live.id(r), zs), has_less_same(L.Live.id(r), zs)))),
        distinct_go(rest, L.Live.less(L.Live.id(r), zs), ys,
          M1.and_r(Bool.not(L.Live.has(L.Live.id(r), rest)), D1.distinct(rest), hm),
          distinct_less(L.Live.id(r), zs, hz)))

def Laws.next_distinct(m, ys, h):
  distinct_go(m, L.Live.of(ys), ys, h, distinct_live(ys))

# --- next_current ---

# an id no record has is the id of no first record
law first_lacks:
  for +i: String
  for m: List<&2, R.Record>
  for +e: {L.Live.has(i, m) == False{} : Bool}
  {D1.first(i, m) == None{} : Maybe<&2, R.Record>}

def first_lacks(i, m, e):
  match m:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      %Equal.sym(Bool, String.eq(L.Live.id(x), i), False{},
        M2.or_fl(String.eq(L.Live.id(x), i), L.Live.has(i, t), e))
        : {D1.first.if(_, x, D1.first(i, t)) == None{} : Maybe<&2, R.Record>}
      first_lacks(i, t, M2.or_fr(String.eq(L.Live.id(x), i), L.Live.has(i, t), e))

# an id no record of a batch has, the batch has no last version of
law find_lacks:
  for +i: String
  for ys: List<&2, R.Record>
  for +e: {L.Live.has(i, ys) == False{} : Bool}
  {L.Live.find(i, ys) == None{} : Maybe<&2, R.Record>}

def find_lacks(i, ys, e):
  match ys:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(Bool, String.eq(L.Live.id(x), i), False{},
        M2.or_fl(String.eq(L.Live.id(x), i), L.Live.has(i, rest), e))
        : {L.Live.found.at(_, _u => L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, L.Live.find(i, rest))
          == None{} : Maybe<&2, R.Record>}
      find_lacks(i, rest, M2.or_fr(String.eq(L.Live.id(x), i), L.Live.has(i, rest), e))

# a record with another id, decided, leaves the first with the id alone
def first_one_miss(
  +i: String,
  h: Bool,
  +r: R.Record,
  f: Maybe<&2, R.Record>,
  +t: List<&2, R.Record>,
  e: {String.eq(L.Live.id(r), i) == False{} : Bool},
  nf: {named(L.Live.id(r), f) == True{} : Bool}
) -> {D1.first(i, L.Live.kept.one(h, r, f, t)) == D1.first(i, t) : Maybe<&2, R.Record>}:
  match h:
    case False{}:
      %Equal.sym(Bool, String.eq(L.Live.id(r), i), False{}, e)
        : {D1.first.if(_, r, D1.first(i, t)) == D1.first(i, t) : Maybe<&2, R.Record>}
      {==}
    case True{}:
      match f:
        case None{}:
          {==}
        case Some{+y}:
          %Equal.sym(String, L.Live.id(y), L.Live.id(r),
            M3.order_eq(L.Live.id(y), L.Live.id(r), EQ{}, nf))
            : {D1.first.if(String.eq(_, i), y, D1.first(i, t)) == D1.first(i, t) : Maybe<&2, R.Record>}
          %Equal.sym(Bool, String.eq(L.Live.id(r), i), False{}, e)
            : {D1.first.if(_, y, D1.first(i, t)) == D1.first(i, t) : Maybe<&2, R.Record>}
          {==}

# first_less_other once it is known whether z has the id left out (c)
def first_less_other.go(
  c: Bool,
  +i: String,
  +j: String,
  +z: R.Record,
  +t: List<&2, R.Record>,
  ec: {String.eq(L.Live.id(z), j) == c : Bool},
  e: {String.eq(j, i) == False{} : Bool},
  ih: {D1.first(i, L.Live.less(j, t)) == D1.first(i, t) : Maybe<&2, R.Record>}
) -> {D1.first(i, L.Live.less.if(c, z, L.Live.less(j, t)))
  == D1.first.if(String.eq(L.Live.id(z), i), z, D1.first(i, t)) : Maybe<&2, R.Record>}:
  match c:
    case False{}:
      %ih
        : {D1.first.if(String.eq(L.Live.id(z), i), z, D1.first(i, L.Live.less(j, t)))
          == D1.first.if(String.eq(L.Live.id(z), i), z, _) : Maybe<&2, R.Record>}
      {==}
    case True{}:
      %Equal.sym(String, L.Live.id(z), j, M3.order_eq(L.Live.id(z), j, EQ{}, ec))
        : {D1.first(i, L.Live.less(j, t)) == D1.first.if(String.eq(_, i), z, D1.first(i, t))
          : Maybe<&2, R.Record>}
      %Equal.sym(Bool, String.eq(j, i), False{}, e)
        : {D1.first(i, L.Live.less(j, t)) == D1.first.if(_, z, D1.first(i, t)) : Maybe<&2, R.Record>}
      ih

# leaving out one id leaves the first record with another id as it was
law first_less_other:
  for +i: String
  for +j: String
  for zs: List<&2, R.Record>
  for +e: {String.eq(j, i) == False{} : Bool}
  {D1.first(i, L.Live.less(j, zs)) == D1.first(i, zs) : Maybe<&2, R.Record>}

def first_less_other(i, j, zs, e):
  match zs:
    case Nil{}:
      {==}
    case Con{+z, +t}:
      first_less_other.go(String.eq(L.Live.id(z), j), i, j, z, t, {==}, e, first_less_other(i, j, t, e))

# nothing either way is nothing
def pick_none(
  hr: Bool
) -> {Bool.pick(Maybe<&2, R.Record>, hr, None{}, None{}) == None{} : Maybe<&2, R.Record>}:
  match hr:
    case True{}:
      {==}
    case False{}:
      {==}

# a record with the id, decided ahead of t, gives the batch's last version
# of the id when the batch names it, else itself: t has no record with the
# id when the batch removes it
law first_one_hit:
  for +i: String
  for hb: Bool
  for +r: R.Record
  for fm: Maybe<&2, R.Record>
  for +t: List<&2, R.Record>
  for hr: Bool
  for -fr: Maybe<&2, R.Record>
  for -zl: Maybe<&2, R.Record>
  for ec: {String.eq(L.Live.id(r), i) == True{} : Bool}
  for nf: {named(i, fm) == True{} : Bool}
  for et: {D1.first(i, t)
    == Bool.pick(Maybe<&2, R.Record>, hr, Bool.pick(Maybe<&2, R.Record>, hb, fm, fr), zl)
    : Maybe<&2, R.Record>}
  for ez: {zl == None{} : Maybe<&2, R.Record>}
  {D1.first(i, L.Live.kept.one(hb, r, fm, t))
  == Bool.pick(Maybe<&2, R.Record>, hb, fm, Some{r}) : Maybe<&2, R.Record>}

def first_one_hit(i, hb, r, fm, t, hr, _fr, zl, ec, nf, et, ez):
  match hb:
    case False{}:
      %Equal.sym(Bool, String.eq(L.Live.id(r), i), True{}, ec)
        : {D1.first.if(_, r, D1.first(i, t)) == Some{r} : Maybe<&2, R.Record>}
      {==}
    case True{}:
      match fm:
        case Some{+y}:
          %Equal.sym(Bool, String.eq(L.Live.id(y), i), True{}, nf)
            : {D1.first.if(_, y, D1.first(i, t)) == Some{y} : Maybe<&2, R.Record>}
          {==}
        case None{}:
          Equal.trans(Maybe<&2, R.Record>, D1.first(i, t),
            Bool.pick(Maybe<&2, R.Record>, hr, None{}, zl), None{}, et,
            (%Equal.sym(Maybe<&2, R.Record>, zl, None{}, ez)
              : {Bool.pick(Maybe<&2, R.Record>, hr, None{}, _) == None{} : Maybe<&2, R.Record>};
              pick_none(hr)))

# the step of current_go once it is known whether r has the id (c)
law current_step:
  for c: Bool
  for +i: String
  for +r: R.Record
  for +rest: List<&2, R.Record>
  for +zs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +ec: {String.eq(L.Live.id(r), i) == c : Bool}
  for ih: {D1.first(i, List.append(&2, R.Record, L.Live.kept(rest, ys),
      L.Live.added(rest, L.Live.less(L.Live.id(r), zs))))
    == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, rest),
      Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, rest)),
      D1.first(i, L.Live.less(L.Live.id(r), zs))) : Maybe<&2, R.Record>}
  {D1.first(i, List.append(&2, R.Record,
    L.Live.kept.one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), L.Live.kept(rest, ys)),
    L.Live.added(rest, L.Live.less(L.Live.id(r), zs))))
  == Bool.pick(Maybe<&2, R.Record>, Bool.or(c, L.Live.has(i, rest)),
    Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys),
      D1.first.if(c, r, D1.first(i, rest))),
    D1.first(i, zs)) : Maybe<&2, R.Record>}

def current_step(c, i, r, rest, zs, ys, ec, ih):
  match c:
    case False{}:
      +k = L.Live.kept(rest, ys)
      +a = L.Live.added(rest, L.Live.less(L.Live.id(r), zs))
      +t = List.append(&2, R.Record, k, a)
      %Equal.sym(List<&2, R.Record>,
        List.append(&2, R.Record,
          L.Live.kept.one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), k), a),
        L.Live.kept.one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), t),
        one_app(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), k, a))
        : {D1.first(i, _)
          == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, rest),
            Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, rest)),
            D1.first(i, zs)) : Maybe<&2, R.Record>}
      Equal.trans(Maybe<&2, R.Record>,
        D1.first(i, L.Live.kept.one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), t)),
        D1.first(i, t),
        Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, rest),
          Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, rest)),
          D1.first(i, zs)),
        first_one_miss(i, L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), t, ec,
          find_named(L.Live.id(r), ys)),
        (%first_less_other(i, L.Live.id(r), zs, ec)
          : {D1.first(i, t)
            == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, rest),
              Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, rest)),
              _) : Maybe<&2, R.Record>};
          ih))
    case True{}:
      +k = L.Live.kept(rest, ys)
      +a = L.Live.added(rest, L.Live.less(L.Live.id(r), zs))
      +t = List.append(&2, R.Record, k, a)
      %Equal.sym(List<&2, R.Record>,
        List.append(&2, R.Record,
          L.Live.kept.one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), k), a),
        L.Live.kept.one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), t),
        one_app(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), k, a))
        : {D1.first(i, _)
          == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), Some{r})
          : Maybe<&2, R.Record>}
      %Equal.sym(String, L.Live.id(r), i, M3.order_eq(L.Live.id(r), i, EQ{}, ec))
        : {D1.first(i, L.Live.kept.one(L.Live.has(_, ys), r, L.Live.find(_, ys), t))
          == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), Some{r})
          : Maybe<&2, R.Record>}
      first_one_hit(i, L.Live.has(i, ys), r, L.Live.find(i, ys), t, L.Live.has(i, rest),
        D1.first(i, rest), D1.first(i, L.Live.less(L.Live.id(r), zs)), ec, find_named(i, ys), ih,
        (%Equal.sym(String, L.Live.id(r), i, M3.order_eq(L.Live.id(r), i, EQ{}, ec))
          : {D1.first(i, L.Live.less(_, zs)) == None{} : Maybe<&2, R.Record>};
          first_lacks(i, L.Live.less(i, zs), has_less_same(i, zs))))

# the record with an id after a batch, the records added being those of zs
# whose ids m lacks: the batch's last version of the id or m's record when m
# has the id, else the first of zs with it
law current_go:
  for +i: String
  for m: List<&2, R.Record>
  for +zs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  {D1.first(i, List.append(&2, R.Record, L.Live.kept(m, ys), L.Live.added(m, zs)))
    == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, m),
      Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, m)),
      D1.first(i, zs)) : Maybe<&2, R.Record>}

def current_go(i, m, zs, ys):
  match m:
    case Nil{}:
      {==}
    case Con{+r, +rest}:
      current_step(String.eq(L.Live.id(r), i), i, r, rest, zs, ys, {==},
        current_go(i, rest, L.Live.less(L.Live.id(r), zs), ys))

# what current_go gives for the batch's own current records, once it is
# known whether m has the id (hm) and whether the batch names it (hy)
def current_end(
  hm: Bool,
  hy: Bool,
  +i: String,
  +m: List<&2, R.Record>,
  +ys: List<&2, R.Record>,
  em: {L.Live.has(i, m) == hm : Bool},
  ey: {L.Live.has(i, ys) == hy : Bool}
) -> {Bool.pick(Maybe<&2, R.Record>, hm,
    Bool.pick(Maybe<&2, R.Record>, hy, L.Live.find(i, ys), D1.first(i, m)),
    D1.first(i, L.Live.of(ys)))
  == Bool.pick(Maybe<&2, R.Record>, hy, L.Live.find(i, ys), D1.first(i, m)) : Maybe<&2, R.Record>}:
  match hm:
    case True{}:
      {==}
    case False{}:
      match hy:
        case True{}:
          %LK.find_live(i, ys)
            : {_ == L.Live.find(i, ys) : Maybe<&2, R.Record>}
          {==}
        case False{}:
          %LK.find_live(i, ys)
            : {_ == D1.first(i, m) : Maybe<&2, R.Record>}
          Equal.trans(Maybe<&2, R.Record>, L.Live.find(i, ys), None{}, D1.first(i, m),
            find_lacks(i, ys, ey),
            Equal.sym(Maybe<&2, R.Record>, D1.first(i, m), None{}, first_lacks(i, m, em)))

def Laws.next_current(i, m, ys):
  Equal.trans(Maybe<&2, R.Record>,
    D1.first(i, L.Live.next(m, ys)),
    Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, m),
      Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, m)),
      D1.first(i, L.Live.of(ys))),
    Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, ys), L.Live.find(i, ys), D1.first(i, m)),
    current_go(i, m, L.Live.of(ys), ys),
    current_end(L.Live.has(i, m), L.Live.has(i, ys), i, m, ys, {==}, {==}))
