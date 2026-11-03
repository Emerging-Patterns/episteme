# packing xs ++ ys freezes what xs froze, then packs on
import Base
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../laws/defs/FrozenShards.bend as D1
import ./AllOfShards.bend as M1
import ./PackingSteps.bend as M2

# the open shard at the end of packing xs after st
def opened(xs: List<&2, R.Record>, +cap: Nat, st: S.Open) -> S.Open:
  match xs:
    case Nil{}:
      st
    case Con{rec, rest}:
      opened(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))

# packing gives the frozen shards, then the open one
law run_eq:
  for xs: List<&2, R.Record>
  for +cap: Nat
  for +st: S.Open
  {S.Shard.run(xs, cap, st)
    == List.append(&2, S.Open, M2.packed(xs, cap, st), [opened(xs, cap, st)])
    : List<&2, S.Open>}

def run_eq(xs, cap, st):
  match xs:
    case Nil{}:
      {==}
    case Con{+rec, +rest}:
      Equal.trans(List<&2, S.Open>,
        S.Shard.run(Con{rec, rest}, cap, st),
        List.append(&2, S.Open, M2.step.out(S.Shard.step(cap, st, rec)),
          S.Shard.run(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))),
        List.append(&2, S.Open, M2.packed(Con{rec, rest}, cap, st),
          [opened(Con{rec, rest}, cap, st)]),
        M2.then_eta(S.Shard.step(cap, st, rec), next => S.Shard.run(rest, cap, next)),
        Equal.trans(List<&2, S.Open>,
          List.append(&2, S.Open, M2.step.out(S.Shard.step(cap, st, rec)),
            S.Shard.run(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))),
          List.append(&2, S.Open, M2.step.out(S.Shard.step(cap, st, rec)),
            List.append(&2, S.Open,
              M2.packed(rest, cap, M2.step.next(S.Shard.step(cap, st, rec))),
              [opened(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))])),
          List.append(&2, S.Open, M2.packed(Con{rec, rest}, cap, st),
            [opened(Con{rec, rest}, cap, st)]),
          Equal.cong(List<&2, S.Open>, List<&2, S.Open>,
            x => List.append(&2, S.Open, M2.step.out(S.Shard.step(cap, st, rec)), x),
            S.Shard.run(rest, cap, M2.step.next(S.Shard.step(cap, st, rec))),
            List.append(&2, S.Open,
              M2.packed(rest, cap, M2.step.next(S.Shard.step(cap, st, rec))),
              [opened(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))]),
            run_eq(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))),
          Equal.sym(List<&2, S.Open>,
            List.append(&2, S.Open,
              List.append(&2, S.Open, M2.step.out(S.Shard.step(cap, st, rec)),
                M2.packed(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))),
              [opened(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))]),
            List.append(&2, S.Open, M2.step.out(S.Shard.step(cap, st, rec)),
              List.append(&2, S.Open,
                M2.packed(rest, cap, M2.step.next(S.Shard.step(cap, st, rec))),
                [opened(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))])),
            M2.lapp_assoc(S.Open, M2.step.out(S.Shard.step(cap, st, rec)),
              M2.packed(rest, cap, M2.step.next(S.Shard.step(cap, st, rec))),
              [opened(rest, cap, M2.step.next(S.Shard.step(cap, st, rec)))]))))

# packing xs ++ ys gives what xs froze, then what ys gives after it
law run_app:
  for xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  for +cap: Nat
  for +st: S.Open
  {S.Shard.run(List.append(&2, R.Record, xs, ys), cap, st)
    == List.append(&2, S.Open, M2.packed(xs, cap, st),
      S.Shard.run(ys, cap, opened(xs, cap, st))) : List<&2, S.Open>}

def run_app(xs, ys, cap, st):
  match xs:
    case Nil{}:
      {==}
    case Con{+rec, +rest}:
      +t = S.Shard.step(cap, st, rec)
      %Equal.sym(List<&2, S.Open>,
        S.Shard.then(t, next => S.Shard.run(List.append(&2, R.Record, rest, ys), cap, next)),
        List.append(&2, S.Open, M2.step.out(t),
          S.Shard.run(List.append(&2, R.Record, rest, ys), cap, M2.step.next(t))),
        M2.then_eta(t, next => S.Shard.run(List.append(&2, R.Record, rest, ys), cap, next)))
        : {_ == List.append(&2, S.Open, M2.packed(Con{rec, rest}, cap, st),
          S.Shard.run(ys, cap, opened(Con{rec, rest}, cap, st))) : List<&2, S.Open>}
      %Equal.sym(List<&2, S.Open>,
        S.Shard.run(List.append(&2, R.Record, rest, ys), cap, M2.step.next(t)),
        List.append(&2, S.Open, M2.packed(rest, cap, M2.step.next(t)),
          S.Shard.run(ys, cap, opened(rest, cap, M2.step.next(t)))),
        run_app(rest, ys, cap, M2.step.next(t)))
        : {List.append(&2, S.Open, M2.step.out(t), _)
          == List.append(&2, S.Open, M2.packed(Con{rec, rest}, cap, st),
          S.Shard.run(ys, cap, opened(Con{rec, rest}, cap, st))) : List<&2, S.Open>}
      Equal.sym(List<&2, S.Open>,
        List.append(&2, S.Open,
          List.append(&2, S.Open, M2.step.out(t), M2.packed(rest, cap, M2.step.next(t))),
          S.Shard.run(ys, cap, opened(rest, cap, M2.step.next(t)))),
        List.append(&2, S.Open, M2.step.out(t),
          List.append(&2, S.Open, M2.packed(rest, cap, M2.step.next(t)),
            S.Shard.run(ys, cap, opened(rest, cap, M2.step.next(t))))),
        M2.lapp_assoc(S.Open, M2.step.out(t), M2.packed(rest, cap, M2.step.next(t)),
          S.Shard.run(ys, cap, opened(rest, cap, M2.step.next(t)))))

# the open shards es, numbered from n, all frozen
def froze(es: List<&2, S.Open>, +n: U32) -> List<&2, S.Shard>:
  match es:
    case Nil{}:
      []
    case Con{e, rest}:
      S.Shard.make(n, e, True{}) <> froze(rest, U32.inc(n))

# numbering es and then shards that follow freezes all of es
law num_app:
  for es: List<&2, S.Open>
  for +gs: List<&2, S.Open>
  for +n: U32
  for +hg: {S.Shard.more(gs) == True{} : Bool}
  {S.Shard.number(List.append(&2, S.Open, es, gs), n)
    == List.append(&2, S.Shard, froze(es, n), S.Shard.number(gs, M1.after(es, n)))
    : List<&2, S.Shard>}

def num_app(es, gs, n, hg):
  match es:
    case Nil{}:
      {==}
    case Con{+e, +rest}:
      %Equal.sym(Bool, S.Shard.more(List.append(&2, S.Open, rest, gs)), True{},
        M2.more_app(rest, gs, hg))
        : {S.Shard.make(n, e, _)
          <> S.Shard.number(List.append(&2, S.Open, rest, gs), U32.inc(n))
          == S.Shard.make(n, e, True{}) <> List.append(&2, S.Shard,
            froze(rest, U32.inc(n)), S.Shard.number(gs, M1.after(rest, U32.inc(n))))
          : List<&2, S.Shard>}
      Equal.cong(List<&2, S.Shard>, List<&2, S.Shard>,
        x => S.Shard.make(n, e, True{}) <> x,
        S.Shard.number(List.append(&2, S.Open, rest, gs), U32.inc(n)),
        List.append(&2, S.Shard, froze(rest, U32.inc(n)),
          S.Shard.number(gs, M1.after(rest, U32.inc(n)))),
        num_app(rest, gs, U32.inc(n), hg))

# the frozen shards of es numbered, then one more, are es frozen
law num_fin:
  for es: List<&2, S.Open>
  for +f: S.Open
  for +n: U32
  {D1.frozen(S.Shard.number(List.append(&2, S.Open, es, [f]), n))
    == froze(es, n) : List<&2, S.Shard>}

def num_fin(es, f, n):
  match es:
    case Nil{}:
      match f:
        case S.Open{_items, _size}:
          {==}
    case Con{e, +rest}:
      match e:
        case S.Open{+items, +size}:
          %Equal.sym(Bool, S.Shard.more(List.append(&2, S.Open, rest, [f])), True{},
            M2.more_app(rest, [f], {==}))
            : {D1.frozen(S.Shard.make(n, S.Open{items, size}, _)
              <> S.Shard.number(List.append(&2, S.Open, rest, [f]), U32.inc(n)))
              == S.Shard.make(n, S.Open{items, size}, True{})
                <> froze(rest, U32.inc(n)) : List<&2, S.Shard>}
          Equal.cong(List<&2, S.Shard>, List<&2, S.Shard>,
            x => S.Shard.make(n, S.Open{items, size}, True{}) <> x,
            D1.frozen(S.Shard.number(List.append(&2, S.Open, rest, [f]),
              U32.inc(n))),
            froze(rest, U32.inc(n)), num_fin(rest, f, U32.inc(n)))
