# proofs of laws/ExtendResumesPack.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/ExtendResumesPack.bend as Laws
import ../laws/defs/FrozenShards.bend as D1
import ../laws/defs/Specification.bend as D2
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/PackingFreezes.bend as M2
import ./lemmas/PackingSteps.bend as M3
import ./lemmas/ShardSizes.bend as M4

# Shard.texts is the specification's texts
def stexts_eq(ps: List<&2, P.Para>) -> {S.Shard.texts(ps) == D2.texts(ps) : Nat}:
  match ps:
    case Nil{}:
      {==}
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _s, _e, +t}:
          Equal.cong(Nat, Nat, z => Nat.add(String.length(t), z),
            S.Shard.texts(rest), D2.texts(rest), stexts_eq(rest))

# Shard.size is the specification's size
def ssize_eq(its: List<&2, S.Item>) -> {S.Shard.size(its) == D2.size(its) : Nat}:
  match its:
    case Nil{}:
      {==}
    case Con{it, rest}:
      match it:
        case S.Item{rec, +from, +upto}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
              Equal.trans(Nat,
                Nat.add(Nat.add(String.length(R.Record.header(R.Record{id, ts, source,
                  author, thread, parent, paras, ptr})),
                  S.Shard.texts(S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                    author, thread, parent, paras, ptr}, from, upto}))),
                  S.Shard.size(rest)),
                Nat.add(Nat.add(String.length(R.Record.header(R.Record{id, ts, source,
                  author, thread, parent, paras, ptr})),
                  D2.texts(S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                    author, thread, parent, paras, ptr}, from, upto}))),
                  S.Shard.size(rest)),
                D2.size(S.Item{R.Record{id, ts, source, author, thread, parent, paras,
                  ptr}, from, upto} <> rest),
                Equal.cong(Nat, Nat,
                  z => Nat.add(Nat.add(String.length(R.Record.header(R.Record{id, ts,
                    source, author, thread, parent, paras, ptr})), z), S.Shard.size(rest)),
                  S.Shard.texts(S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                    author, thread, parent, paras, ptr}, from, upto})),
                  D2.texts(S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                    author, thread, parent, paras, ptr}, from, upto})),
                  stexts_eq(S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                    author, thread, parent, paras, ptr}, from, upto}))),
                Equal.cong(Nat, Nat,
                  z => Nat.add(Nat.add(String.length(R.Record.header(R.Record{id, ts,
                    source, author, thread, parent, paras, ptr})),
                    D2.texts(S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                      author, thread, parent, paras, ptr}, from, upto}))), z),
                  S.Shard.size(rest), D2.size(rest), ssize_eq(rest)))

# P of the last of es ++ [f]
def all_last(
  -P: S.Open -> Type,
  es: List<&2, S.Open>,
  -f: S.Open,
  a: M1.All(S.Open, P, List.append(&2, S.Open, es, [f]))
) -> P(f):
  match es:
    case Nil{}:
      match a:
        case (pf, _u):
          pf
    case Con{_e, t}:
      match a:
        case (_p, r):
          all_last(P, t, f, r)

# the last of es ++ [f] numbered from n is f, the tail, numbered after es
def final_number(
  es: List<&2, S.Open>,
  +f: S.Open,
  +n: U32,
  -d: S.Shard
) -> {D2.final(S.Shard.number(List.append(&2, S.Open, es, [f]), n), d)
  == S.Shard.make(M1.after(es, n), f, False{}) : S.Shard}:
  match es:
    case Nil{}:
      {==}
    case Con{+e, +rest}:
      final_number(rest, f, U32.inc(n),
        S.Shard.make(n, e, S.Shard.more(List.append(&2, S.Open, rest, [f]))))

# extending the tail made of the open shard f resumes packing from f
def extend_make(
  +cap: U32,
  +k: U32,
  f: S.Open,
  +ys: List<&2, R.Record>,
  h: M4.szeq(f)
) -> {S.Shard.extend(cap, S.Shard.make(k, f, False{}), ys)
  == S.Shard.number(S.Shard.run(ys, U32.to_nat(cap), f), k) : List<&2, S.Shard>}:
  match f:
    case S.Open{+items, +size}:
      Equal.cong(Nat, List<&2, S.Shard>,
        z => S.Shard.number(S.Shard.run(ys, U32.to_nat(cap), S.Open{items, z}), k),
        S.Shard.size(items), size,
        Equal.trans(Nat, S.Shard.size(items), D2.size(items), size,
          ssize_eq(items), h))

# laws/ExtendResumesPack.bend: extending the tail of pack(cap, n, xs) with ys gives what
# pack(cap, n, xs ++ ys) gives after the frozen shards of pack(cap, n, xs)
def Laws.extend_pack(cap, n, xs, ys, hc):
  +c = U32.to_nat(cap)
  +st = {S.Open{[], 0n} : S.Open}
  +es = M3.packed(xs, c, st)
  +f = M2.opened(xs, c, st)
  +d = {S.Shard{1, [], [], 0, False{}} : S.Shard}
  +tl = S.Shard.number(S.Shard.run(ys, c, f), M1.after(es, n))
  +ext = S.Shard.extend(cap, D2.final(S.Shard.pack(cap, n, xs), d), ys)
  szf = all_last(M4.szeq, es, f,
    (%M2.run_eq(xs, c, st) : M1.All(S.Open, M4.szeq, _)
    M4.run_sz(xs, c, st, {==}, hc)))
  lhs = Equal.trans(List<&2, S.Shard>,
    S.Shard.number(S.Shard.run(List.append(&2, R.Record, xs, ys), c, st), n),
    S.Shard.number(List.append(&2, S.Open, es, S.Shard.run(ys, c, f)), n),
    List.append(&2, S.Shard, M2.froze(es, n), tl),
    Equal.cong(List<&2, S.Open>, List<&2, S.Shard>, z => S.Shard.number(z, n),
      S.Shard.run(List.append(&2, R.Record, xs, ys), c, st),
      List.append(&2, S.Open, es, S.Shard.run(ys, c, f)), M2.run_app(xs, ys, c, st)),
    M2.num_app(es, S.Shard.run(ys, c, f), n, M3.run_more(ys, c, f)))
  fa = Equal.trans(List<&2, S.Shard>,
    D1.frozen(S.Shard.number(S.Shard.run(xs, c, st), n)),
    D1.frozen(S.Shard.number(List.append(&2, S.Open, es, [f]), n)),
    M2.froze(es, n),
    Equal.cong(List<&2, S.Open>, List<&2, S.Shard>,
      z => D1.frozen(S.Shard.number(z, n)), S.Shard.run(xs, c, st),
      List.append(&2, S.Open, es, [f]), M2.run_eq(xs, c, st)),
    M2.num_fin(es, f, n))
  eb = Equal.trans(List<&2, S.Shard>,
    ext,
    S.Shard.extend(cap, D2.final(S.Shard.number(List.append(&2, S.Open, es, [f]), n), d),
      ys),
    tl,
    Equal.cong(List<&2, S.Open>, List<&2, S.Shard>,
      z => S.Shard.extend(cap, D2.final(S.Shard.number(z, n), d), ys),
      S.Shard.run(xs, c, st), List.append(&2, S.Open, es, [f]), M2.run_eq(xs, c, st)),
    Equal.trans(List<&2, S.Shard>,
      S.Shard.extend(cap, D2.final(S.Shard.number(List.append(&2, S.Open, es, [f]), n),
        d), ys),
      S.Shard.extend(cap, S.Shard.make(M1.after(es, n), f, False{}), ys),
      tl,
      Equal.cong(S.Shard, List<&2, S.Shard>, sh => S.Shard.extend(cap, sh, ys),
        D2.final(S.Shard.number(List.append(&2, S.Open, es, [f]), n), d),
        S.Shard.make(M1.after(es, n), f, False{}), final_number(es, f, n, d)),
      extend_make(cap, M1.after(es, n), f, ys, szf)))
  Equal.trans(List<&2, S.Shard>,
    S.Shard.number(S.Shard.run(List.append(&2, R.Record, xs, ys), c, st), n),
    List.append(&2, S.Shard, M2.froze(es, n), tl),
    List.append(&2, S.Shard, D1.frozen(S.Shard.pack(cap, n, xs)), ext),
    lhs,
    Equal.sym(List<&2, S.Shard>,
      List.append(&2, S.Shard, D1.frozen(S.Shard.pack(cap, n, xs)), ext),
      List.append(&2, S.Shard, M2.froze(es, n), tl),
      Equal.trans(List<&2, S.Shard>,
        List.append(&2, S.Shard, D1.frozen(S.Shard.pack(cap, n, xs)), ext),
        List.append(&2, S.Shard, M2.froze(es, n), ext),
        List.append(&2, S.Shard, M2.froze(es, n), tl),
        Equal.cong(List<&2, S.Shard>, List<&2, S.Shard>,
          z => List.append(&2, S.Shard, z, ext),
          D1.frozen(S.Shard.pack(cap, n, xs)), M2.froze(es, n), fa),
        Equal.cong(List<&2, S.Shard>, List<&2, S.Shard>,
          z => List.append(&2, S.Shard, M2.froze(es, n), z), ext, tl, eb))))
