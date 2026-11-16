# proofs of laws/SourceShardsHoldCurrentRecords.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ../laws/SourceShardsHoldCurrentRecords.bend as Laws
import ../laws/LiveKeepsLastVersion.bend as LK
import ../laws/ShardsGiveBackRecords.bend as GB
import ../laws/ExtendResumesPack.bend as ER
import ../laws/defs/CurrentRecords.bend as D1
import ../laws/defs/Specification.bend as D2
import ../laws/defs/FrozenShards.bend as D3
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

# a record kept or not keeps the current records apart
def apart_put(
  h: Bool,
  g: Bool,
  +x: R.Record,
  +rest: List<&2, R.Record>,
  eh: {L.Live.has(L.Live.id(x), rest) == h : Bool},
  ih: {D1.apart(L.Live.of(rest), None{}) == True{} : Bool}
) -> {D1.apart(L.Live.put(h, g, x, L.Live.of(rest)), None{}) == True{} : Bool}:
  match h:
    case True{}:
      ih
    case False{}:
      match g:
        case True{}:
          ih
        case False{}:
          Equal.trans(Bool, D1.apart(L.Live.of(rest), Some{L.Live.id(x)}),
            D1.apart(L.Live.of(rest), None{}), True{},
            apart_some(L.Live.id(x), L.Live.of(rest), M1.has_live(L.Live.id(x), rest, eh)), ih)

# no current record has the id of the one before it
law apart_live:
  for xs: List<&2, R.Record>
  {D1.apart(L.Live.of(xs), None{}) == True{} : Bool}

def apart_live(xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      apart_put(L.Live.has(L.Live.id(x), rest), L.Live.gone(x), x, rest, {==}, apart_live(rest))

def Laws.repack_live(cap, xs, ys, hc, hf):
  %Equal.sym(List<&2, R.Record>, L.Live.held(S.Shard.pack(cap, 1, L.Live.of(xs))), L.Live.of(xs),
    GB.held_pack(cap, 1, L.Live.of(xs), counted_live(xs, hc), filled_live(xs, hf), apart_live(xs)))
    : {S.Shard.pack(cap, 1, L.Live.of(List.append(&2, R.Record, _, ys)))
      == S.Shard.pack(cap, 1, L.Live.of(List.append(&2, R.Record, xs, ys))) : List<&2, S.Shard>}
  %LK.live_append(xs, ys)
    : {S.Shard.pack(cap, 1, L.Live.of(List.append(&2, R.Record, L.Live.of(xs), ys)))
      == S.Shard.pack(cap, 1, _) : List<&2, S.Shard>}
  {==}

def Laws.extend_live(cap, n, xs, ys, hc, hy, hf):
  %Equal.sym(List<&2, R.Record>, L.Live.of(List.append(&2, R.Record, xs, ys)),
    List.append(&2, R.Record, L.Live.of(xs), L.Live.of(ys)), LK.live_fresh(xs, ys, hf))
    : {S.Shard.pack(cap, n, _)
      == List.append(&2, S.Shard, D3.frozen(S.Shard.pack(cap, n, L.Live.of(xs))),
        S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, L.Live.of(xs)), S.Shard{1, [], [], 0, False{}}),
          ys)) : List<&2, S.Shard>}
  %Equal.sym(List<&2, R.Record>, L.Live.of(ys), ys, hy)
    : {S.Shard.pack(cap, n, List.append(&2, R.Record, L.Live.of(xs), _))
      == List.append(&2, S.Shard, D3.frozen(S.Shard.pack(cap, n, L.Live.of(xs))),
        S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, L.Live.of(xs)), S.Shard{1, [], [], 0, False{}}),
          ys)) : List<&2, S.Shard>}
  ER.extend_pack(cap, n, L.Live.of(xs), ys, counted_live(xs, hc))
