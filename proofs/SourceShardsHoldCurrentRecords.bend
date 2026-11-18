# proofs of laws/SourceShardsHoldCurrentRecords.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ../laws/SourceShardsHoldCurrentRecords.bend as Laws
import ../laws/ChangedRecordKeepsItsPlace.bend as CK
import ../laws/ShardsGiveBackRecords.bend as GB
import ../laws/ExtendResumesPack.bend as ER
import ../laws/defs/CurrentRecords.bend as D1
import ../laws/defs/Specification.bend as D2
import ../laws/defs/FrozenShards.bend as D3
import ./ChangedRecordKeepsItsPlace.bend as P1
import ./lemmas/BoolFacts.bend as M0
import ./lemmas/CurrentFacts.bend as M1

# a record kept or not keeps every record counted
def counted_put(
  h: Bool,
  g: Bool,
  -x: R.Record,
  -m: List<&2, R.Record>,
  cx: {U32.to_nat(U32.from_nat(D2.rec.count(x))) == D2.rec.count(x) : Nat},
  cm: D2.counted(m)
) -> D2.counted(L.Live.put(h, g, x, m)):
  match h:
    case True{}:
      cm
    case False{}:
      match g:
        case True{}:
          cm
        case False{}:
          (cx, cm)

# the current records of counted records are counted
law counted_live:
  for xs: List<&2, R.Record>
  for hc: D2.counted(xs)
  D2.counted(L.Live.of(xs))

def counted_live(xs, hc):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match hc:
        case (cx, cr):
          counted_put(L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, L.Live.of(rest), cx,
            counted_live(rest, cr))

# a record kept or not keeps every record with a paragraph
def filled_put(
  h: Bool,
  g: Bool,
  -x: R.Record,
  -m: List<&2, R.Record>,
  fx: {D2.full(D2.rec.paras(x)) == True{} : Bool},
  fm: D1.filled(m)
) -> D1.filled(L.Live.put(h, g, x, m)):
  match h:
    case True{}:
      fm
    case False{}:
      match g:
        case True{}:
          fm
        case False{}:
          (fx, fm)

# the current records of records with a paragraph each have one
law filled_live:
  for xs: List<&2, R.Record>
  for hf: D1.filled(xs)
  D1.filled(L.Live.of(xs))

def filled_live(xs, hf):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match hf:
        case (fx, fr):
          filled_put(L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, L.Live.of(rest), fx,
            filled_live(rest, fr))

# records none of which has the id l are apart from l as from nothing
law apart_some:
  for +l: String
  for m: List<&2, R.Record>
  for e: {L.Live.has(l, m) == False{} : Bool}
  {D1.apart(m, Some{l}) == D1.apart(m, None{}) : Bool}

def apart_some(l, m, e):
  match m:
    case Nil{}:
      {==}
    case Con{+y, +t}:
      %Equal.sym(Bool, String.eq(L.Live.id(y), l), False{},
        M1.or_fl(String.eq(L.Live.id(y), l), L.Live.has(l, t), e))
        : {Bool.and(Bool.not(_), D1.apart(t, Some{L.Live.id(y)}))
          == D1.apart(t, Some{L.Live.id(y)}) : Bool}
      {==}

# records no two of which have one id are apart
law apart_distinct:
  for m: List<&2, R.Record>
  for +hd: {D1.distinct(m) == True{} : Bool}
  {D1.apart(m, None{}) == True{} : Bool}

def apart_distinct(m, hd):
  match m:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      Equal.trans(Bool, D1.apart(rest, Some{L.Live.id(x)}), D1.apart(rest, None{}), True{},
        apart_some(L.Live.id(x), rest, M1.not_t(L.Live.has(L.Live.id(x), rest),
          M0.and_l(Bool.not(L.Live.has(L.Live.id(x), rest)), D1.distinct(rest), hd))),
        apart_distinct(rest, M0.and_r(Bool.not(L.Live.has(L.Live.id(x), rest)), D1.distinct(rest), hd)))

def Laws.repack_live(cap, m, ys, hc, hf, hd):
  %Equal.sym(List<&2, R.Record>, L.Live.held(S.Shard.pack(cap, 1, m)), m,
    GB.held_pack(cap, 1, m, hc, hf, apart_distinct(m, hd)))
    : {S.Shard.pack(cap, 1, L.Live.next(_, ys)) == S.Shard.pack(cap, 1, L.Live.next(m, ys))
      : List<&2, S.Shard>}
  {==}

def Laws.extend_live(cap, n, m, ys, hc, hy, hf):
  %Equal.sym(List<&2, R.Record>, L.Live.next(m, ys), List.append(&2, R.Record, m, L.Live.of(ys)),
    CK.next_new(m, ys, hf))
    : {S.Shard.pack(cap, n, _)
      == List.append(&2, S.Shard, D3.frozen(S.Shard.pack(cap, n, m)),
        S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, m), S.Shard{1, [], [], 0, False{}}),
          ys)) : List<&2, S.Shard>}
  %Equal.sym(List<&2, R.Record>, L.Live.of(ys), ys, hy)
    : {S.Shard.pack(cap, n, List.append(&2, R.Record, m, _))
      == List.append(&2, S.Shard, D3.frozen(S.Shard.pack(cap, n, m)),
        S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, m), S.Shard{1, [], [], 0, False{}}),
          ys)) : List<&2, S.Shard>}
  ER.extend_pack(cap, n, m, ys, hc)

# --- next_counted ---

# every record of xs has fewer than 2^32 paragraphs, as a fact that can be
# used more than once
def counted_d(xs: List<&2, R.Record>) -> Data:
  match xs:
    case Nil{}:
      Unit
    case Con{+r, tail}:
      Sigma<&2, &2, {U32.to_nat(U32.from_nat(D2.rec.count(r))) == D2.rec.count(r) : Nat},
        _h => counted_d(tail)>

# counted records are counted as a fact that can be used more than once
def counted_many(xs: List<&2, R.Record>, hc: D2.counted(xs)) -> counted_d(xs):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match hc:
        case (cx, cr):
          (cx, counted_many(rest, cr))

# and back
def counted_once(xs: List<&2, R.Record>, hc: counted_d(xs)) -> D2.counted(xs):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match hc:
        case (cx, cr):
          (cx, counted_once(rest, cr))

# counted records followed by counted records are counted
def counted_app(
  a: List<&2, R.Record>,
  -b: List<&2, R.Record>,
  ca: D2.counted(a),
  cb: D2.counted(b)
) -> D2.counted(List.append(&2, R.Record, a, b)):
  match a:
    case Nil{}:
      cb
    case Con{+x, +t}:
      match ca:
        case (cx, ct):
          (cx, counted_app(t, b, ct, cb))

# what a find step gives is counted when the record and the rest's find are
def counted_found(
  e: Bool,
  h: Bool,
  g: Bool,
  -x: R.Record,
  -nx: Maybe<&2, R.Record>,
  cx: {U32.to_nat(U32.from_nat(D2.rec.count(x))) == D2.rec.count(x) : Nat},
  cn: D2.counted(D1.given(nx))
) -> D2.counted(D1.given(L.Live.found.at(e, _u => h, g, x, nx))):
  match e:
    case False{}:
      cn
    case True{}:
      match h:
        case True{}:
          cn
        case False{}:
          match g:
            case True{}:
              Unit{}
            case False{}:
              (cx, Unit{})

# the last version a counted batch gives an id is counted
def counted_find(
  +j: String,
  ys: List<&2, R.Record>,
  cy: counted_d(ys)
) -> D2.counted(D1.given(L.Live.find(j, ys))):
  match ys:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match cy:
        case (cx, cr):
          counted_found(String.eq(L.Live.id(x), j), L.Live.has(L.Live.id(x), rest), L.Live.gone(x),
            x, L.Live.find(j, rest), cx, counted_find(j, rest, cr))

# a counted record decided ahead of counted records leaves them counted
def counted_one(
  h: Bool,
  -r: R.Record,
  f: Maybe<&2, R.Record>,
  -t: List<&2, R.Record>,
  cr: {U32.to_nat(U32.from_nat(D2.rec.count(r))) == D2.rec.count(r) : Nat},
  cf: D2.counted(D1.given(f)),
  ct: D2.counted(t)
) -> D2.counted(L.Live.kept.one(h, r, f, t)):
  match h:
    case False{}:
      (cr, ct)
    case True{}:
      match f:
        case None{}:
          ct
        case Some{y}:
          match cf:
            case (cy, _u):
              (cy, ct)

# counted records after a counted batch are counted
def counted_kept(
  m: List<&2, R.Record>,
  +ys: List<&2, R.Record>,
  cm: D2.counted(m),
  +cy: counted_d(ys)
) -> D2.counted(L.Live.kept(m, ys)):
  match m:
    case Nil{}:
      Unit{}
    case Con{+r, +rest}:
      match cm:
        case (cr, cs):
          counted_one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), L.Live.kept(rest, ys),
            cr, counted_find(L.Live.id(r), ys, cy), counted_kept(rest, ys, cs, cy))

# a record ahead or not of counted records leaves them counted
def counted_less_if(
  hit: Bool,
  -z: R.Record,
  -t: List<&2, R.Record>,
  cz: {U32.to_nat(U32.from_nat(D2.rec.count(z))) == D2.rec.count(z) : Nat},
  ct: D2.counted(t)
) -> D2.counted(L.Live.less.if(hit, z, t)):
  match hit:
    case True{}:
      ct
    case False{}:
      (cz, ct)

# counted records without an id are counted
def counted_less(
  +j: String,
  zs: List<&2, R.Record>,
  cz: D2.counted(zs)
) -> D2.counted(L.Live.less(j, zs)):
  match zs:
    case Nil{}:
      Unit{}
    case Con{+z, +t}:
      match cz:
        case (cx, ct):
          counted_less_if(String.eq(L.Live.id(z), j), z, L.Live.less(j, t), cx, counted_less(j, t, ct))

# the counted records m lacks are counted
def counted_added(
  m: List<&2, R.Record>,
  +zs: List<&2, R.Record>,
  cz: D2.counted(zs)
) -> D2.counted(L.Live.added(m, zs)):
  match m:
    case Nil{}:
      cz
    case Con{+r, +rest}:
      counted_added(rest, L.Live.less(L.Live.id(r), zs), counted_less(L.Live.id(r), zs, cz))

def Laws.next_counted(m, ys, hm, hy):
  +dy = counted_many(ys, hy)
  counted_app(L.Live.kept(m, ys), L.Live.added(m, L.Live.of(ys)), counted_kept(m, ys, hm, dy),
    counted_added(m, L.Live.of(ys), counted_live(ys, counted_once(ys, dy))))

# --- next_filled ---

# every record of xs has a paragraph, as a fact that can be used more than
# once
def filled_d(xs: List<&2, R.Record>) -> Data:
  match xs:
    case Nil{}:
      Unit
    case Con{+r, tail}:
      Sigma<&2, &2, {D2.full(D2.rec.paras(r)) == True{} : Bool}, _h => filled_d(tail)>

# records with a paragraph each have one as a fact that can be used more
# than once
def filled_many(xs: List<&2, R.Record>, hf: D1.filled(xs)) -> filled_d(xs):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match hf:
        case (fx, fr):
          (fx, filled_many(rest, fr))

# and back
def filled_once(xs: List<&2, R.Record>, hf: filled_d(xs)) -> D1.filled(xs):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match hf:
        case (fx, fr):
          (fx, filled_once(rest, fr))

# records with a paragraph each, followed by such records, each have one
def filled_app(
  a: List<&2, R.Record>,
  -b: List<&2, R.Record>,
  ca: D1.filled(a),
  cb: D1.filled(b)
) -> D1.filled(List.append(&2, R.Record, a, b)):
  match a:
    case Nil{}:
      cb
    case Con{+x, +t}:
      match ca:
        case (fx, ft):
          (fx, filled_app(t, b, ft, cb))

# what a find step gives has a paragraph when the record and the rest's find do
def filled_found(
  e: Bool,
  h: Bool,
  g: Bool,
  -x: R.Record,
  -nx: Maybe<&2, R.Record>,
  fx: {D2.full(D2.rec.paras(x)) == True{} : Bool},
  fn: D1.filled(D1.given(nx))
) -> D1.filled(D1.given(L.Live.found.at(e, _u => h, g, x, nx))):
  match e:
    case False{}:
      fn
    case True{}:
      match h:
        case True{}:
          fn
        case False{}:
          match g:
            case True{}:
              Unit{}
            case False{}:
              (fx, Unit{})

# the last version a batch of records with a paragraph gives an id has one
def filled_find(
  +j: String,
  ys: List<&2, R.Record>,
  fy: filled_d(ys)
) -> D1.filled(D1.given(L.Live.find(j, ys))):
  match ys:
    case Nil{}:
      Unit{}
    case Con{+x, +rest}:
      match fy:
        case (fx, fr):
          filled_found(String.eq(L.Live.id(x), j), L.Live.has(L.Live.id(x), rest), L.Live.gone(x),
            x, L.Live.find(j, rest), fx, filled_find(j, rest, fr))

# a record with a paragraph decided ahead of such records leaves each with one
def filled_one(
  h: Bool,
  -r: R.Record,
  f: Maybe<&2, R.Record>,
  -t: List<&2, R.Record>,
  fr: {D2.full(D2.rec.paras(r)) == True{} : Bool},
  ff: D1.filled(D1.given(f)),
  ft: D1.filled(t)
) -> D1.filled(L.Live.kept.one(h, r, f, t)):
  match h:
    case False{}:
      (fr, ft)
    case True{}:
      match f:
        case None{}:
          ft
        case Some{y}:
          match ff:
            case (fy, _u):
              (fy, ft)

# records with a paragraph each, after a batch of such records, each have one
def filled_kept(
  m: List<&2, R.Record>,
  +ys: List<&2, R.Record>,
  fm: D1.filled(m),
  +fy: filled_d(ys)
) -> D1.filled(L.Live.kept(m, ys)):
  match m:
    case Nil{}:
      Unit{}
    case Con{+r, +rest}:
      match fm:
        case (fr, fs):
          filled_one(L.Live.has(L.Live.id(r), ys), r, L.Live.find(L.Live.id(r), ys), L.Live.kept(rest, ys),
            fr, filled_find(L.Live.id(r), ys, fy), filled_kept(rest, ys, fs, fy))

# a record with a paragraph, ahead or not of such records, leaves each with one
def filled_less_if(
  hit: Bool,
  -z: R.Record,
  -t: List<&2, R.Record>,
  fz: {D2.full(D2.rec.paras(z)) == True{} : Bool},
  ft: D1.filled(t)
) -> D1.filled(L.Live.less.if(hit, z, t)):
  match hit:
    case True{}:
      ft
    case False{}:
      (fz, ft)

# records with a paragraph each, without an id, each have one
def filled_less(
  +j: String,
  zs: List<&2, R.Record>,
  fz: D1.filled(zs)
) -> D1.filled(L.Live.less(j, zs)):
  match zs:
    case Nil{}:
      Unit{}
    case Con{+z, +t}:
      match fz:
        case (fx, ft):
          filled_less_if(String.eq(L.Live.id(z), j), z, L.Live.less(j, t), fx, filled_less(j, t, ft))

# the records with a paragraph each that m lacks each have one
def filled_added(
  m: List<&2, R.Record>,
  +zs: List<&2, R.Record>,
  fz: D1.filled(zs)
) -> D1.filled(L.Live.added(m, zs)):
  match m:
    case Nil{}:
      fz
    case Con{+r, +rest}:
      filled_added(rest, L.Live.less(L.Live.id(r), zs), filled_less(L.Live.id(r), zs, fz))

def Laws.next_filled(m, ys, hm, hy):
  +dy = filled_many(ys, hy)
  filled_app(L.Live.kept(m, ys), L.Live.added(m, L.Live.of(ys)), filled_kept(m, ys, hm, dy),
    filled_added(m, L.Live.of(ys), filled_live(ys, filled_once(ys, dy))))
