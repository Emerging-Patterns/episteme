# proofs of laws/FailedReadsListed.bend
import Base
import ../src/read.bend as Rd
import ../laws/FailedReadsListed.bend as Laws
import ../laws/defs/FrozenShards.bend as D1

# a read's failing list after its ok test is the code's
law failed_one:
  for ok: Bool
  for r: Rd.Read
  for rest: List<&2, Rd.Read>
  for ih: {Rd.Read.failed(rest) == Laws.failing(rest) : List<&2, Rd.Read>}
  {Rd.Read.failed.if(ok, r, Rd.Read.failed(rest))
    == List.append(&2, Rd.Read, Laws.failing.one(ok, r), Laws.failing(rest))
    : List<&2, Rd.Read>}

def failed_one(ok, r, rest, ih):
  match ok:
    case True{}:
      ih
    case False{}:
      Equal.cong(List<&2, Rd.Read>, List<&2, Rd.Read>, ys => r <> ys,
        Rd.Read.failed(rest), Laws.failing(rest), ih)

def Laws.failed_spec(rs):
  match rs:
    case Nil{}:
      {==}
    case Con{r, +rest}:
      match r:
        case Rd.Read{shard, inst, labels, +ok, why, pn, pm, cn, ms}:
          failed_one(ok, Rd.Read{shard, inst, labels, ok, why, pn, pm, cn, ms}, rest,
            Laws.failed_spec(rest))

# a read's code after its ok test is the specification's
law code_one:
  for ok: Bool
  for rest: List<&2, Rd.Read>
  for ih: {Rd.Read.code(rest) == D1.flag(Laws.any_failed(rest)) : U32}
  {Rd.Read.code.if(ok, _u => Rd.Read.code(rest))
    == D1.flag(Bool.or(Bool.not(ok), Laws.any_failed(rest))) : U32}

def code_one(ok, _rest, ih):
  match ok:
    case True{}:
      ih
    case False{}:
      {==}

def Laws.code_failed(rs):
  match rs:
    case Nil{}:
      {==}
    case Con{r, +rest}:
      match r:
        case Rd.Read{_shard, _inst, _labels, ok, _why, _pn, _pm, _cn, _ms}:
          code_one(ok, rest, Laws.code_failed(rest))
