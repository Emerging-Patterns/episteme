# proofs of laws/ShowReadsOneSource.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ../laws/ShowReadsOneSource.bend as Laws
import ../laws/ChangedRecordKeepsItsPlace.bend as CK
import ../laws/SourceShardsHoldCurrentRecords.bend as SH
import ../laws/ShardsGiveBackRecords.bend as GB
import ../laws/defs/CurrentRecords.bend as D1
import ../laws/defs/Specification.bend as D2
import ./SourceShardsHoldCurrentRecords.bend as P1
import ./ChangedRecordKeepsItsPlace.bend as P2
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/CurrentFacts.bend as M2
import ./lemmas/TextOrder.bend as M3

# a text with no "@" names no source
law none_noat:
  for key: String
  for +h: {Laws.noat(key) == True{} : Bool}
  {L.Live.source(key) == None{} : Maybe<&2, String>}

def none_noat(key, h):
  match key:
    case SNil{}:
      {==}
    case SCon{+chr, +rest}:
      %Equal.sym(Maybe<&2, String>, L.Live.source(rest), None{},
        none_noat(rest, M1.and_r(Bool.not(Char.is_eq(chr, '@')), Laws.noat(rest), h)))
        : {L.Live.cut.if(Char.is_eq(chr, '@'), chr, _) == None{} : Maybe<&2, String>}
      %Equal.sym(Bool, Char.is_eq(chr, '@'), False{},
        M2.not_t(Char.is_eq(chr, '@'), M1.and_l(Bool.not(Char.is_eq(chr, '@')), Laws.noat(rest), h)))
        : {L.Live.cut.if(_, chr, None{}) == None{} : Maybe<&2, String>}
      {==}

def Laws.source_named(src, key, h):
  match src:
    case SNil{}:
      %Equal.sym(Maybe<&2, String>, L.Live.source(key), None{}, none_noat(key, h))
        : {L.Live.cut.if(Char.is_eq('@', '@'), '@', _) == Some{""} : Maybe<&2, String>}
      {==}
    case SCon{+chr, +rest}:
      %Equal.sym(Maybe<&2, String>, L.Live.source(String.append(rest, SCon{'@', key})), Some{rest},
        Laws.source_named(rest, key, h))
        : {L.Live.cut.if(Char.is_eq(chr, '@'), chr, _) == Some{SCon{chr, rest}} : Maybe<&2, String>}
      {==}

# the pick of a record kept or not past a hit
def pick_if(
  b: Bool,
  -rec: R.Record,
  -m: Maybe<&2, R.Record>
) -> {L.Live.pick.if(b, rec, m) == D1.first.if(b, rec, m) : Maybe<&2, R.Record>}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# show's pick is the specification's first record with the id
law pick_first:
  for +id: String
  for xs: List<&2, R.Record>
  {L.Live.pick(id, xs) == D1.first(id, xs) : Maybe<&2, R.Record>}

def pick_first(id, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %pick_first(id, rest)
        : {L.Live.pick.if(String.eq(L.Live.id(x), id), x, L.Live.pick(id, rest))
          == D1.first.if(String.eq(L.Live.id(x), id), x, _) : Maybe<&2, R.Record>}
      pick_if(String.eq(L.Live.id(x), id), x, L.Live.pick(id, rest))

# --- show_shards ---

# the last version of an id nothing follows: itself when the id is named,
# else none
def find_end(
  h: Bool,
  +i: String,
  +f: List<&2, R.Record>,
  +e: {L.Live.has(i, f) == h : Bool}
) -> {L.Live.find(i, f) == Bool.pick(Maybe<&2, R.Record>, h, L.Live.find(i, f), None{})
  : Maybe<&2, R.Record>}:
  match h:
    case True{}:
      {==}
    case False{}:
      P2.find_lacks(i, f, e)

# what a record with the id gives when f follows the rest: the last version
# f gives when f names the id (hf), else what it gives without f; a is
# whether the rest names the id, l whether the rest followed by f does
def found_app(
  hf: Bool,
  a: Bool,
  -l: Bool,
  -g: Bool,
  -x: R.Record,
  -n: Maybe<&2, R.Record>,
  -ff: Maybe<&2, R.Record>,
  -fr: Maybe<&2, R.Record>,
  el: {l == Bool.or(a, hf) : Bool},
  ih: {n == Bool.pick(Maybe<&2, R.Record>, hf, ff, fr) : Maybe<&2, R.Record>}
) -> {L.Live.found(l, g, x, n) == Bool.pick(Maybe<&2, R.Record>, hf, ff, L.Live.found(a, g, x, fr))
  : Maybe<&2, R.Record>}:
  match hf:
    case True{}:
      %Equal.sym(Bool, l, True{}, Equal.trans(Bool, l, Bool.or(a, True{}), True{}, el,
        M2.or_t(a, True{}, {==})))
        : {L.Live.found(_, g, x, n) == ff : Maybe<&2, R.Record>}
      ih
    case False{}:
      %Equal.sym(Bool, l, a, Equal.trans(Bool, l, Bool.or(a, False{}), a, el, M2.or_f(a)))
        : {L.Live.found(_, g, x, n) == L.Live.found(a, g, x, fr) : Maybe<&2, R.Record>}
      %Equal.sym(Maybe<&2, R.Record>, n, fr, ih)
        : {L.Live.found(a, g, x, _) == L.Live.found(a, g, x, fr) : Maybe<&2, R.Record>}
      {==}

# the step of find_app once it is known whether x has the id (c)
law find_app_step:
  for c: Bool
  for hf: Bool
  for +i: String
  for +x: R.Record
  for +rest: List<&2, R.Record>
  for +f: List<&2, R.Record>
  for +ec: {String.eq(L.Live.id(x), i) == c : Bool}
  for ef: {L.Live.has(i, f) == hf : Bool}
  for ih: {L.Live.find(i, List.append(&2, R.Record, rest, f))
    == Bool.pick(Maybe<&2, R.Record>, hf, L.Live.find(i, f), L.Live.find(i, rest))
    : Maybe<&2, R.Record>}
  {L.Live.found.at(c, _u => L.Live.has(L.Live.id(x), List.append(&2, R.Record, rest, f)),
    L.Live.gone(x), x, L.Live.find(i, List.append(&2, R.Record, rest, f)))
  == Bool.pick(Maybe<&2, R.Record>, hf, L.Live.find(i, f),
    L.Live.found.at(c, _u => L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, L.Live.find(i, rest)))
  : Maybe<&2, R.Record>}

def find_app_step(c, hf, i, x, rest, f, ec, ef, ih):
  match c:
    case False{}:
      ih
    case True{}:
      found_app(hf, L.Live.has(L.Live.id(x), rest),
        L.Live.has(L.Live.id(x), List.append(&2, R.Record, rest, f)), L.Live.gone(x), x,
        L.Live.find(i, List.append(&2, R.Record, rest, f)), L.Live.find(i, f), L.Live.find(i, rest),
        (%ef
          : {L.Live.has(L.Live.id(x), List.append(&2, R.Record, rest, f))
            == Bool.or(L.Live.has(L.Live.id(x), rest), _) : Bool};
          %M3.order_eq(L.Live.id(x), i, EQ{}, ec)
            : {L.Live.has(L.Live.id(x), List.append(&2, R.Record, rest, f))
              == Bool.or(L.Live.has(L.Live.id(x), rest), L.Live.has(_, f)) : Bool};
          M2.has_app(L.Live.id(x), rest, f)),
        ih)

# the last version of an id in b followed by f is the one f gives when f
# names the id, else the one b gives
law find_app:
  for +i: String
  for b: List<&2, R.Record>
  for +f: List<&2, R.Record>
  {L.Live.find(i, List.append(&2, R.Record, b, f))
    == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, f), L.Live.find(i, f), L.Live.find(i, b))
    : Maybe<&2, R.Record>}

def find_app(i, b, f):
  match b:
    case Nil{}:
      find_end(L.Live.has(i, f), i, f, {==})
    case Con{+x, +rest}:
      find_app_step(String.eq(L.Live.id(x), i), L.Live.has(i, f), i, x, rest, f, {==}, {==},
        find_app(i, rest, f))

# a later batch's version, else an earlier batch's, else m's: the same
# whether the two batches are asked one after the other or as one
def pick_or(
  hf: Bool,
  hb: Bool,
  -ff: Maybe<&2, R.Record>,
  -fb: Maybe<&2, R.Record>,
  -fm: Maybe<&2, R.Record>
) -> {Bool.pick(Maybe<&2, R.Record>, hf, ff, Bool.pick(Maybe<&2, R.Record>, hb, fb, fm))
  == Bool.pick(Maybe<&2, R.Record>, Bool.or(hb, hf), Bool.pick(Maybe<&2, R.Record>, hf, ff, fb), fm)
  : Maybe<&2, R.Record>}:
  match hf:
    case True{}:
      match hb:
        case True{}:
          {==}
        case False{}:
          {==}
    case False{}:
      match hb:
        case True{}:
          {==}
        case False{}:
          {==}

# the step of after_current: fn is the record after the first batch, ha and
# fa what the first batch followed by the rest names and gives
def after_step(
  hf: Bool,
  hb: Bool,
  -ha: Bool,
  -ff: Maybe<&2, R.Record>,
  -fb: Maybe<&2, R.Record>,
  -fa: Maybe<&2, R.Record>,
  -fm: Maybe<&2, R.Record>,
  -fn: Maybe<&2, R.Record>,
  en: {fn == Bool.pick(Maybe<&2, R.Record>, hb, fb, fm) : Maybe<&2, R.Record>},
  eh: {ha == Bool.or(hb, hf) : Bool},
  ef: {fa == Bool.pick(Maybe<&2, R.Record>, hf, ff, fb) : Maybe<&2, R.Record>}
) -> {Bool.pick(Maybe<&2, R.Record>, hf, ff, fn) == Bool.pick(Maybe<&2, R.Record>, ha, fa, fm)
  : Maybe<&2, R.Record>}:
  %Equal.sym(Maybe<&2, R.Record>, fn, Bool.pick(Maybe<&2, R.Record>, hb, fb, fm), en)
    : {Bool.pick(Maybe<&2, R.Record>, hf, ff, _) == Bool.pick(Maybe<&2, R.Record>, ha, fa, fm)
      : Maybe<&2, R.Record>}
  %Equal.sym(Bool, ha, Bool.or(hb, hf), eh)
    : {Bool.pick(Maybe<&2, R.Record>, hf, ff, Bool.pick(Maybe<&2, R.Record>, hb, fb, fm))
      == Bool.pick(Maybe<&2, R.Record>, _, fa, fm) : Maybe<&2, R.Record>}
  %Equal.sym(Maybe<&2, R.Record>, fa, Bool.pick(Maybe<&2, R.Record>, hf, ff, fb), ef)
    : {Bool.pick(Maybe<&2, R.Record>, hf, ff, Bool.pick(Maybe<&2, R.Record>, hb, fb, fm))
      == Bool.pick(Maybe<&2, R.Record>, Bool.or(hb, hf), _, fm) : Maybe<&2, R.Record>}
  pick_or(hf, hb, ff, fb, fm)

# the record with an id after batches is the last version their records
# give in log order when they name the id, else the one m had
law after_current:
  for +i: String
  for bs: List<&2, List<&2, R.Record>>
  for +m: List<&2, R.Record>
  {D1.first(i, D1.after(bs, m))
    == Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, D1.flat(bs)), L.Live.find(i, D1.flat(bs)),
      D1.first(i, m)) : Maybe<&2, R.Record>}

def after_current(i, bs, m):
  match bs:
    case Nil{}:
      {==}
    case Con{+b, +rest}:
      Equal.trans(Maybe<&2, R.Record>,
        D1.first(i, D1.after(rest, L.Live.next(m, b))),
        Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, D1.flat(rest)), L.Live.find(i, D1.flat(rest)),
          D1.first(i, L.Live.next(m, b))),
        Bool.pick(Maybe<&2, R.Record>, L.Live.has(i, List.append(&2, R.Record, b, D1.flat(rest))),
          L.Live.find(i, List.append(&2, R.Record, b, D1.flat(rest))), D1.first(i, m)),
        after_current(i, rest, L.Live.next(m, b)),
        after_step(L.Live.has(i, D1.flat(rest)), L.Live.has(i, b),
          L.Live.has(i, List.append(&2, R.Record, b, D1.flat(rest))),
          L.Live.find(i, D1.flat(rest)), L.Live.find(i, b),
          L.Live.find(i, List.append(&2, R.Record, b, D1.flat(rest))),
          D1.first(i, m), D1.first(i, L.Live.next(m, b)),
          CK.next_current(i, m, b), M2.has_app(i, b, D1.flat(rest)), find_app(i, b, D1.flat(rest))))

# records no two of which have one id stay so after batches
law after_distinct:
  for bs: List<&2, List<&2, R.Record>>
  for +m: List<&2, R.Record>
  for hd: {D1.distinct(m) == True{} : Bool}
  {D1.distinct(D1.after(bs, m)) == True{} : Bool}

def after_distinct(bs, m, hd):
  match bs:
    case Nil{}:
      hd
    case Con{+b, +rest}:
      after_distinct(rest, L.Live.next(m, b), CK.next_distinct(m, b, hd))

# counted records stay counted after batches of counted records
law after_counted:
  for bs: List<&2, List<&2, R.Record>>
  for +m: List<&2, R.Record>
  for hm: D2.counted(m)
  for hb: D1.counted_all(bs)
  D2.counted(D1.after(bs, m))

def after_counted(bs, m, hm, hb):
  match bs:
    case Nil{}:
      hm
    case Con{+b, +rest}:
      match hb:
        case (cb, cr):
          after_counted(rest, L.Live.next(m, b), SH.next_counted(m, b, hm, cb), cr)

# records that each have a paragraph stay so after batches of such records
law after_filled:
  for bs: List<&2, List<&2, R.Record>>
  for +m: List<&2, R.Record>
  for hm: D1.filled(m)
  for hb: D1.filled_all(bs)
  D1.filled(D1.after(bs, m))

def after_filled(bs, m, hm, hb):
  match bs:
    case Nil{}:
      hm
    case Con{+b, +rest}:
      match hb:
        case (fb, fr):
          after_filled(rest, L.Live.next(m, b), SH.next_filled(m, b, hm, fb), fr)

def Laws.show_shards(cap, id, bs, hc, hf):
  %Equal.sym(List<&2, R.Record>, L.Live.held(S.Shard.pack(cap, 1, D1.after(bs, []))), D1.after(bs, []),
    GB.held_pack(cap, 1, D1.after(bs, []), after_counted(bs, [], Unit{}, hc),
      after_filled(bs, [], Unit{}, hf), P1.apart_distinct(D1.after(bs, []), after_distinct(bs, [], {==}))))
    : {L.Live.pick(id, _) == L.Live.find(id, D1.flat(bs)) : Maybe<&2, R.Record>}
  Equal.trans(Maybe<&2, R.Record>, L.Live.pick(id, D1.after(bs, [])), D1.first(id, D1.after(bs, [])),
    L.Live.find(id, D1.flat(bs)), pick_first(id, D1.after(bs, [])),
    Equal.trans(Maybe<&2, R.Record>, D1.first(id, D1.after(bs, [])),
      Bool.pick(Maybe<&2, R.Record>, L.Live.has(id, D1.flat(bs)), L.Live.find(id, D1.flat(bs)), None{}),
      L.Live.find(id, D1.flat(bs)), after_current(id, bs, []),
      Equal.sym(Maybe<&2, R.Record>, L.Live.find(id, D1.flat(bs)),
        Bool.pick(Maybe<&2, R.Record>, L.Live.has(id, D1.flat(bs)), L.Live.find(id, D1.flat(bs)), None{}),
        find_end(L.Live.has(id, D1.flat(bs)), id, D1.flat(bs), {==}))))
