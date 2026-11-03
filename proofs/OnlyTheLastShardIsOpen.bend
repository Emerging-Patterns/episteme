# proofs of laws/OnlyTheLastShardIsOpen.bend
import Base
import ../src/shard.bend as S
import ../laws/OnlyTheLastShardIsOpen.bend as Laws
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/PackingSteps.bend as M2

# numbering g ahead of rest from num chains
law num_chain:
  for rest: List<&2, S.Open>
  for g: S.Open
  for +num: U32
  Laws.chain.go(S.Shard.number(rest, U32.inc(num)),
    S.Shard.make(num, g, S.Shard.more(rest)), num)

def num_chain(rest, g, num):
  match rest g:
    case Nil{} S.Open{_items, _size}:
      ({==}, {==})
    case Con{g2, r2} S.Open{_items, _size}:
      ({==}, ({==}, num_chain(r2, g2, U32.inc(num))))

# numbering shards that follow chains
def num_chain_more(
  gs: List<&2, S.Open>,
  +num: U32,
  e: {S.Shard.more(gs) == True{} : Bool}
) -> Laws.chain(S.Shard.number(gs, num), num):
  match gs:
    case Nil{}:
      Empty.absurd(Laws.chain([], num), M1.clash(e))
    case Con{g, rest}:
      num_chain(rest, g, num)

# laws/OnlyTheLastShardIsOpen.bend: shards are numbered from n, all frozen but the tail
def Laws.shard_frozen(cap, n, xs):
  +c = U32.to_nat(cap)
  num_chain_more(S.Shard.run(xs, c, S.Open{[], 0n}), n, M2.run_more(xs, c, S.Open{[], 0n}))
