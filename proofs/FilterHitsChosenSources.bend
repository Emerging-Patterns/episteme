# proofs of laws/FilterHitsChosenSources.bend
import Base
import ../src/shard.bend as S
import ../src/filter.bend as F
import ../laws/FilterHitsChosenSources.bend as Laws
import ../laws/SourceDirsAreSafeAndDistinct.bend as L1
import ../laws/defs/SourceSelection.bend as D1
import ./lemmas/OffsetsHeld.bend as M1
import ./lemmas/TextOrder.bend as M2

# a lazy or with nothing after it is its first value
law any_if_none:
  for b: Bool
  {List.any.if(_u => False{}, b) == b : Bool}

def any_if_none(b):
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

# the code's selector test is the specification's
law selects_eq:
  for sel: F.Sel
  for +src: String
  {F.Filter.selects(sel, src) == D1.selects(sel, src) : Bool}

def selects_eq(sel, _src):
  match sel:
    case F.Exact{_t}:
      {==}
    case F.Prefix{_t}:
      {==}

# the code's test over the selectors is the specification's
law picks_eq:
  for +sels: List<&2, F.Sel>
  for +src: String
  {F.Filter.picks(sels, src) == D1.picked(sels, src) : Bool}

def picks_eq(sels, src):
  match sels:
    case Nil{}:
      {==}
    case Con{+sel, +rest}:
      %selects_eq(sel, src) : {List.any.if(_u => F.Filter.picks(rest, src),
        F.Filter.selects(sel, src))
        == Bool.or(_, D1.picked(rest, src)) : Bool}
      M1.any_if_or(F.Filter.selects(sel, src), F.Filter.picks(rest, src),
        D1.picked(rest, src), picks_eq(rest, src))

def Laws.filter_hits(sels, srcs):
  match srcs:
    case Nil{}:
      {==}
    case Con{+src, +rest}:
      %picks_eq(sels, src) : {List.any.if(_u => F.Filter.hits(sels, rest),
        F.Filter.picks(sels, src))
        == Bool.or(_, D1.overlaps(sels, rest)) : Bool}
      M1.any_if_or(F.Filter.picks(sels, src), F.Filter.hits(sels, rest),
        D1.overlaps(sels, rest), Laws.filter_hits(sels, rest))

# laws/FilterHitsChosenSources.bend: ask's directory test: the name reads back as the source
# (laws/SourceDirsAreSafeAndDistinct.bend),
# which the filter picks exactly when it hits a shard of that source
def Laws.reads_dir(sels, src):
  %Equal.sym(Maybe<&2, String>, S.Shard.undir(S.Shard.dir(src)), Some{src}, L1.dir_round(src))
    : {F.Filter.reads.of(sels, _) == F.Filter.hits(sels, [src]) : Bool}
  Equal.sym(Bool, List.any.if(_u => False{}, F.Filter.picks(sels, src)),
    F.Filter.picks(sels, src), any_if_none(F.Filter.picks(sels, src)))
