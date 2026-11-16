# proofs of laws/ShardsGiveBackRecords.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/live.bend as L
import ../laws/ShardsGiveBackRecords.bend as Laws
import ../laws/ShardsCoverEveryParagraph.bend as SC
import ../laws/defs/CurrentRecords.bend as D1
import ../laws/defs/Specification.bend as D2
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/CoverAndLabels.bend as M2
import ./lemmas/CurrentFacts.bend as M3
import ./lemmas/PackingSteps.bend as M4

# the lines Live reads are the specification's cover of the shards' items
law lines_cover:
  for ss: List<&2, S.Shard>
  {L.Live.lines(ss) == SC.shards.cover(ss) : List<&2, S.Shard.Line()>}

def lines_cover(ss):
  match ss:
    case Nil{}:
      {==}
    case Con{sh, +rest}:
      match sh:
        case S.Shard{_n, +items, _sources, _chars, _frozen}:
          %M2.lines_same(items)
            : {List.append(&2, S.Shard.Line(), S.Shard.lines(items), L.Live.lines(rest))
              == List.append(&2, S.Shard.Line(), _, SC.shards.cover(rest))
              : List<&2, S.Shard.Line()>}
          %lines_cover(rest)
            : {List.append(&2, S.Shard.Line(), S.Shard.lines(items), L.Live.lines(rest))
              == List.append(&2, S.Shard.Line(), S.Shard.lines(items), _)
              : List<&2, S.Shard.Line()>}
          {==}

# a record's own lines after its first add nothing
law skip_pairs:
  for +x: R.Record
  for ps: List<&2, P.Para>
  for +c: List<&2, S.Shard.Line()>
  {L.Live.firsts(List.append(&2, S.Shard.Line(), D2.pairs(x, ps), c), Some{L.Live.id(x)})
    == L.Live.firsts(c, Some{L.Live.id(x)}) : List<&2, R.Record>}

def skip_pairs(x, ps, c):
  match ps:
    case Nil{}:
      {==}
    case Con{_p, +qs}:
      %Equal.sym(Bool, String.eq(L.Live.id(x), L.Live.id(x)), True{}, M4.eq_refl(L.Live.id(x)))
        : {L.Live.firsts.if(_, x,
            L.Live.firsts(List.append(&2, S.Shard.Line(), D2.pairs(x, qs), c), Some{L.Live.id(x)}))
          == L.Live.firsts(c, Some{L.Live.id(x)}) : List<&2, R.Record>}
      skip_pairs(x, qs, c)

# the first record of the cover, then the rest
def head_step(
  +x: R.Record,
  ps: List<&2, P.Para>,
  +rest: List<&2, R.Record>,
  +last: Maybe<&2, String>,
  fx: {D2.full(ps) == True{} : Bool},
  es: {L.Live.same(last, L.Live.id(x)) == False{} : Bool},
  ih: {L.Live.firsts(D2.cover(rest), Some{L.Live.id(x)}) == rest : List<&2, R.Record>}
) -> {L.Live.firsts(List.append(&2, S.Shard.Line(), D2.pairs(x, ps), D2.cover(rest)), last)
  == x <> rest : List<&2, R.Record>}:
  match ps:
    case Nil{}:
      Empty.absurd({L.Live.firsts(D2.cover(rest), last) == x <> rest : List<&2, R.Record>},
        M1.clash(fx))
    case Con{_p, +qs}:
      %Equal.sym(Bool, L.Live.same(last, L.Live.id(x)), False{}, es)
        : {L.Live.firsts.if(_, x,
            L.Live.firsts(List.append(&2, S.Shard.Line(), D2.pairs(x, qs), D2.cover(rest)),
              Some{L.Live.id(x)}))
          == x <> rest : List<&2, R.Record>}
      Equal.cong(List<&2, R.Record>, List<&2, R.Record>, l => x <> l,
        L.Live.firsts(List.append(&2, S.Shard.Line(), D2.pairs(x, qs), D2.cover(rest)),
          Some{L.Live.id(x)}), rest,
        Equal.trans(List<&2, R.Record>,
          L.Live.firsts(List.append(&2, S.Shard.Line(), D2.pairs(x, qs), D2.cover(rest)),
            Some{L.Live.id(x)}),
          L.Live.firsts(D2.cover(rest), Some{L.Live.id(x)}), rest,
          skip_pairs(x, qs, D2.cover(rest)), ih))

# the cover of records, read back from last on, is the records
law firsts_cover:
  for xs: List<&2, R.Record>
  for +last: Maybe<&2, String>
  for hf: D1.filled(xs)
  for +ha: {D1.apart(xs, last) == True{} : Bool}
  {L.Live.firsts(D2.cover(xs), last) == xs : List<&2, R.Record>}

def firsts_cover(xs, last, hf, ha):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      match hf:
        case (fx, fr):
          head_step(x, D2.rec.paras(x), rest, last, fx,
            M3.not_t(L.Live.same(last, L.Live.id(x)),
              M1.and_l(Bool.not(L.Live.same(last, L.Live.id(x))), D1.apart(rest, Some{L.Live.id(x)}), ha)),
            firsts_cover(rest, Some{L.Live.id(x)}, fr,
              M1.and_r(Bool.not(L.Live.same(last, L.Live.id(x))), D1.apart(rest, Some{L.Live.id(x)}), ha)))

def Laws.held_pack(cap, n, xs, hc, hf, ha):
  Equal.trans(List<&2, R.Record>,
    L.Live.firsts(L.Live.lines(S.Shard.pack(cap, n, xs)), None{}),
    L.Live.firsts(D2.cover(xs), None{}), xs,
    Equal.cong(List<&2, S.Shard.Line()>, List<&2, R.Record>, l => L.Live.firsts(l, None{}),
      L.Live.lines(S.Shard.pack(cap, n, xs)), D2.cover(xs),
      Equal.trans(List<&2, S.Shard.Line()>, L.Live.lines(S.Shard.pack(cap, n, xs)),
        SC.shards.cover(S.Shard.pack(cap, n, xs)), D2.cover(xs),
        lines_cover(S.Shard.pack(cap, n, xs)), SC.shard_cover(cap, n, xs, hc))),
    firsts_cover(xs, None{}, hf, ha))
