# proofs of laws/FrozenShardsFitCap.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/FrozenShardsFitCap.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/BoolFacts.bend as M2
import ./lemmas/NatArithmetic.bend as M3
import ./lemmas/ShardSizes.bend as M4

# an open shard's size is at most cap
def leq(+cap: Nat, g: S.Open) -> Type:
  {Nat.is_le(M4.open.size(g), cap) == True{} : Bool}

# what cut_le gives for the rest, after the next paragraph joined the piece
# or not
def cut_le.ih(
  b: Bool,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  +l: Nat,
  +rest: List<&2, P.Para>
) -> Type:
  {Nat.is_le(Nat.add(h, S.Shard.cut.sz(b, sz, l)), cap) == True{} : Bool}
    -> M1.StepAll(g => leq(cap, g), S.Shard.cut(rest, cap, rec, h, S.Shard.cut.j(b, j, m),
      S.Shard.cut.m(b, m), S.Shard.cut.sz(b, sz, l)))

# leq after the next paragraph joined the piece or not
def cut_le.if(
  b: Bool,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  +l: Nat,
  +rest: List<&2, P.Para>,
  eb: {Nat.is_le(Nat.add(h, Nat.add(sz, l)), cap) == b : Bool},
  hle: {Nat.is_le(Nat.add(h, sz), cap) == True{} : Bool},
  hp: {Nat.is_le(Nat.add(h, l), cap) == True{} : Bool},
  ih: cut_le.ih(b, cap, rec, h, j, m, sz, l, rest)
) -> M1.StepAll(g => leq(cap, g), S.Shard.cut.if(b, rec, h, j, m, sz, S.Shard.cut(rest, cap, rec, h, S.Shard.cut.j(b, j,
  m), S.Shard.cut.m(b, m), S.Shard.cut.sz(b, sz, l)))):
  match b:
    case True{}:
      ih(eb)
    case False{}:
      M1.emit_all(g => leq(cap, g), S.Open{[S.Shard.piece(rec, j, m)], Nat.add(h, sz)},
        S.Shard.cut(rest, cap, rec, h, Nat.add(j, 1n+m), 0n, l), hle, ih(hp))

# every piece cut from ps fits in cap, when each paragraph fits beside the
# header line
def cut_le(
  ps: List<&2, P.Para>,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  hle: {Nat.is_le(Nat.add(h, sz), cap) == True{} : Bool},
  room: Laws.roomy.paras(cap, h, ps)
) -> M1.StepAll(g => leq(cap, g), S.Shard.cut(ps, cap, rec, h, j, m, sz)):
  match ps:
    case Nil{}:
      (Unit{}, hle)
    case Con{pa, +rest}:
      match pa:
        case P.Para{_pn, _pstart, _pend, +text}:
          match room:
            case (hp, rr):
              cut_le.if(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap),
                cap, rec, h, j, m, sz, String.length(text), rest, {==}, hle, hp,
                h2 => cut_le(rest, cap, rec, h,
                  S.Shard.cut.j(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), j, m),
                  S.Shard.cut.m(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), m),
                  S.Shard.cut.sz(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap),
                    sz, String.length(text)), h2, rr))

# every shard a record cut gives fits in cap
def split_le(
  rec: R.Record,
  +cap: Nat,
  hh: {Nat.is_le(D1.rec.head(rec), cap) == True{} : Bool},
  room: Laws.roomy.paras(cap, D1.rec.head(rec), D1.rec.paras(rec))
) -> M1.StepAll(g => leq(cap, g), S.Shard.split(S.Shard.paras(rec), cap, rec, R.Record.size(rec))):
  match rec:
    case R.Record{+id, +ts, +source, +author, +thread, +parent, paras, +ptr}:
      match paras:
        case Nil{}:
          (Unit{},
            (%Equal.sym(Nat,
              Nat.add(String.length(R.Record.header(R.Record{id, ts, source, author,
                thread, parent, [], ptr})), 0n),
              String.length(R.Record.header(R.Record{id, ts, source, author, thread,
                parent, [], ptr})),
              M3.add_zero_r(String.length(R.Record.header(R.Record{id, ts, source, author,
                thread, parent, [], ptr}))))
              : {Nat.is_le(_, cap) == True{} : Bool}
            hh))
        case Con{pa, +rest}:
          match pa:
            case P.Para{+pn, +pstart, +pend, +text}:
              match room:
                case (hp, rr):
                  cut_le(rest, cap, R.Record{id, ts, source, author, thread, parent,
                    P.Para{pn, pstart, pend, text} <> rest, ptr},
                    String.length(R.Record.header(R.Record{id, ts, source, author,
                      thread, parent, P.Para{pn, pstart, pend, text} <> rest, ptr})),
                    0n, 0n, String.length(text), hp, rr)

# every shard a record whole or cut gives fits in cap
def lay_le(
  small: Bool,
  +cap: Nat,
  +rec: R.Record,
  e: {Nat.is_le(R.Record.size(rec), cap) == small : Bool},
  hh: {Nat.is_le(D1.rec.head(rec), cap) == True{} : Bool},
  room: Laws.roomy.paras(cap, D1.rec.head(rec), D1.rec.paras(rec))
) -> M1.StepAll(g => leq(cap, g), S.Shard.lay.if(small, cap, rec, R.Record.size(rec))):
  match small:
    case True{}:
      (Unit{}, e)
    case False{}:
      split_le(rec, cap, hh, room)

# every shard a step gives fits in cap
def step_le.if(
  fits: Bool,
  +cap: Nat,
  +cur: List<&2, S.Item>,
  +size: Nat,
  +rec: R.Record,
  e: {Nat.is_le(Nat.add(size, R.Record.size(rec)), cap) == fits : Bool},
  hh: {Nat.is_le(D1.rec.head(rec), cap) == True{} : Bool},
  room: Laws.roomy.paras(cap, D1.rec.head(rec), D1.rec.paras(rec)),
  hst: leq(cap, S.Open{cur, size})
) -> M1.StepAll(g => leq(cap, g), S.Shard.step.if(fits, cap, cur, size, rec, R.Record.size(rec))):
  match fits:
    case True{}:
      (Unit{}, e)
    case False{}:
      M1.after_all(g => leq(cap, g), S.Shard.shut(cur, size),
        S.Shard.lay.if(Nat.is_le(R.Record.size(rec), cap), cap, rec, R.Record.size(rec)),
        M1.shut_all(g => leq(cap, g), cur, size, hst),
        lay_le(Nat.is_le(R.Record.size(rec), cap), cap, rec, {==}, hh, room))

# every shard a step gives fits in cap
def step_le(
  +cap: Nat,
  st: S.Open,
  +rec: R.Record,
  hh: {Nat.is_le(D1.rec.head(rec), cap) == True{} : Bool},
  room: Laws.roomy.paras(cap, D1.rec.head(rec), D1.rec.paras(rec)),
  hst: leq(cap, st)
) -> M1.StepAll(g => leq(cap, g), S.Shard.step(cap, st, rec)):
  match st:
    case S.Open{+cur, +size}:
      step_le.if(Nat.is_le(Nat.add(size, R.Record.size(rec)), cap), cap, cur, size,
        rec, {==}, hh, room, hst)

# every shard packing gives fits in cap
def run_le(
  xs: List<&2, R.Record>,
  +cap: Nat,
  +st: S.Open,
  hst: leq(cap, st),
  hx: Laws.roomy(cap, xs)
) -> M1.All(S.Open, g => leq(cap, g), S.Shard.run(xs, cap, st)):
  match xs:
    case Nil{}:
      (hst, Unit{})
    case Con{+rec, +rest}:
      match hx:
        case (hh, (room, hrest)):
          M1.then_all(g => leq(cap, g), S.Shard.step(cap, st, rec), rest, cap,
            step_le(cap, st, rec, hh, room, hst),
            o => ho => run_le(rest, cap, o, ho, hrest))

# the claim of laws/FrozenShardsFitCap.bend about one shard
def size_ok(+cap: Nat, +s: S.Shard) -> Type:
  Pair({Nat.is_le(D1.size(D1.shard.items(s)), cap) == True{} : Bool},
    {Laws.shard.chars(s) == U32.from_nat(D1.size(D1.shard.items(s))) : U32})

# laws/FrozenShardsFitCap.bend of a shard made of items whose size is size
def size_made.go(
  +cap: Nat,
  -k: U32,
  +items: List<&2, S.Item>,
  +size: Nat,
  -f: Bool,
  +hs: {D1.size(items) == size : Nat},
  hl: {Nat.is_le(size, cap) == True{} : Bool}
) -> size_ok(cap, S.Shard.make(k, S.Open{items, size}, f)):
  ((%Equal.sym(Nat, D1.size(items), size, hs)
    : {Nat.is_le(_, cap) == True{} : Bool}
    hl),
    Equal.cong(Nat, U32, x => U32.from_nat(x), size, D1.size(items),
      Equal.sym(Nat, D1.size(items), size, hs)))

# laws/FrozenShardsFitCap.bend of a made shard
def size_made(
  +cap: Nat,
  +k: U32,
  g: S.Open,
  +f: Bool,
  hb: Pair(M4.szeq(g), leq(cap, g))
) -> size_ok(cap, S.Shard.make(k, g, f)):
  match g:
    case S.Open{+items, +size}:
      match hb:
        case (hs, hl):
          size_made.go(cap, k, items, size, f, hs, hl)

# All of P and All of Q make All of both
def all_both(
  -A: Data,
  -Pa: A -> Type,
  -Qa: A -> Type,
  xs: List<&2, A>,
  ap: M1.All(A, Pa, xs),
  aq: M1.All(A, Qa, xs)
) -> M1.All(A, x => Pair(Pa(x), Qa(x)), xs):
  match xs:
    case Nil{}:
      Unit{}
    case Con{_h, t}:
      match ap:
        case (p1, pt):
          match aq:
            case (q1, qt):
              ((p1, q1), all_both(A, Pa, Qa, t, pt, qt))

# laws/FrozenShardsFitCap.bend of a shard made of one of gs
def size_in(
  gs: List<&2, S.Open>,
  +cap: Nat,
  -s: S.Shard,
  ok: M1.All(S.Open, g => Pair(M4.szeq(g), leq(cap, g)), gs),
  m: M1.made_in(gs, s)
) -> size_ok(cap, s):
  match m:
    case (g, (k, (f, (el, e)))):
      %Equal.sym(S.Shard, s, S.Shard.make(k, g, f), e) : size_ok(cap, _)
      size_made(cap, k, g, f,
        M1.all_elem(S.Open, g2 => Pair(M4.szeq(g2), leq(cap, g2)), gs, g, ok, el))

# laws/FrozenShardsFitCap.bend: every shard fits in cap, and its chars is its size
def Laws.shard_size(cap, n, xs, hc, hr, s, hs):
  +c = U32.to_nat(cap)
  +gs = S.Shard.run(xs, c, S.Open{[], 0n})
  size_in(gs, c, s, all_both(S.Open, M4.szeq, g => leq(c, g), gs,
    M4.run_sz(xs, c, S.Open{[], 0n}, {==}, hc),
    run_le(xs, c, S.Open{[], 0n}, M2.zero_le(c), hr)), M1.number_elem(gs, n, s, hs))
