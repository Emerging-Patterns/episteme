# proofs of laws/ShowReadsOneSource.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ../laws/ShowReadsOneSource.bend as Laws
import ../laws/LiveKeepsLastVersion.bend as LK
import ../laws/ShardsGiveBackRecords.bend as GB
import ../laws/defs/CurrentRecords.bend as D1
import ./SourceShardsHoldCurrentRecords.bend as P1
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/CurrentFacts.bend as M2

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

def Laws.show_shards(cap, id, xs, hc, hf):
  %Equal.sym(List<&2, R.Record>, L.Live.held(S.Shard.pack(cap, 1, L.Live.of(xs))), L.Live.of(xs),
    GB.held_pack(cap, 1, L.Live.of(xs), P1.counted_live(xs, hc), P1.filled_live(xs, hf), P1.apart_live(xs)))
    : {L.Live.pick(id, _) == L.Live.find(id, xs) : Maybe<&2, R.Record>}
  Equal.trans(Maybe<&2, R.Record>, L.Live.pick(id, L.Live.of(xs)), D1.first(id, L.Live.of(xs)),
    L.Live.find(id, xs), pick_first(id, L.Live.of(xs)),
    Equal.sym(Maybe<&2, R.Record>, L.Live.find(id, xs), D1.first(id, L.Live.of(xs)), LK.find_live(id, xs)))
