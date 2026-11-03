# Every shard but the last is frozen; the last is the tail even if full;
# shards are numbered consecutively from `next_n`.
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/FrozenShards.bend as D1

# a shard's number
def shard.n(sh: S.Shard) -> U32:
  match sh:
    case S.Shard{num, _items, _sources, _chars, _frozen}:
      num

# prev numbered num, then the shards ss numbered from num + 1: each but the
# last frozen, and the last not
def chain.go(ss: List<&2, S.Shard>, +prev: S.Shard, +num: U32) -> Type:
  match ss:
    case Nil{}:
      Pair({shard.n(prev) == num : U32}, {D1.shard.frozen(prev) == False{} : Bool})
    case Con{head, tail}:
      Pair({shard.n(prev) == num : U32},
        Pair({D1.shard.frozen(prev) == True{} : Bool}, chain.go(tail, head, U32.inc(num))))

# ss is not empty and is numbered num, num + 1, ... in order, each shard
# frozen but the last, which is not
def chain(ss: List<&2, S.Shard>, +num: U32) -> Type:
  match ss:
    case Nil{}:
      Empty
    case Con{head, tail}:
      chain.go(tail, head, num)

# LAW: packing gives at least one shard; they are numbered n, n + 1, ... in
# order, and every one but the last is frozen while the last, the tail, is
# not, even when full
law shard_frozen:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  chain(S.Shard.pack(cap, n, xs), n)
