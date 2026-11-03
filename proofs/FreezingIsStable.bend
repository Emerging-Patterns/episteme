# proofs of laws/FreezingIsStable.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/FreezingIsStable.bend as Laws
import ../laws/defs/FrozenShards.bend as D1
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/PackingFreezes.bend as M2
import ./lemmas/PackingSteps.bend as M3

# laws/FreezingIsStable.bend: packing xs ++ ys starts with the frozen shards of packing xs
def Laws.shard_stable(cap, n, xs, ys):
  +c = U32.to_nat(cap)
  +st = {S.Open{[], 0n} : S.Open}
  +es = M3.packed(xs, c, st)
  +f = M2.opened(xs, c, st)
  +zs = S.Shard.number(S.Shard.run(ys, c, f), M1.after(es, n))
  (zs,
    %Equal.sym(List<&2, S.Open>, S.Shard.run(List.append(&2, R.Record, xs, ys), c, st),
      List.append(&2, S.Open, es, S.Shard.run(ys, c, f)), M2.run_app(xs, ys, c, st))
      : {S.Shard.number(_, n) == List.append(&2, S.Shard,
        D1.frozen(S.Shard.pack(cap, n, xs)), zs) : List<&2, S.Shard>}
    %Equal.sym(List<&2, S.Open>, S.Shard.run(xs, c, st),
      List.append(&2, S.Open, es, [f]), M2.run_eq(xs, c, st))
      : {S.Shard.number(List.append(&2, S.Open, es, S.Shard.run(ys, c, f)), n)
        == List.append(&2, S.Shard, D1.frozen(S.Shard.number(_, n)), zs)
        : List<&2, S.Shard>}
    %Equal.sym(List<&2, S.Shard>,
      D1.frozen(S.Shard.number(List.append(&2, S.Open, es, [f]), n)),
      M2.froze(es, n), M2.num_fin(es, f, n))
      : {S.Shard.number(List.append(&2, S.Open, es, S.Shard.run(ys, c, f)), n)
        == List.append(&2, S.Shard, _, zs) : List<&2, S.Shard>}
    M2.num_app(es, S.Shard.run(ys, c, f), n, M3.run_more(ys, c, f)))
