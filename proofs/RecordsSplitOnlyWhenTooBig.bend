# proofs of laws/RecordsSplitOnlyWhenTooBig.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/RecordsSplitOnlyWhenTooBig.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ../laws/defs/Specification.bend as D2
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/BoolFacts.bend as M2

# laws/RecordsSplitOnlyWhenTooBig.bend: Record.chars is a record's size
def Laws.chars_size(r):
  Equal.cong(Nat, U32, x => U32.from_nat(x), R.Record.size(r), Laws.rsize(r),
    M1.size_same(r))

# an item of a record that fits in cap is the whole record
def okit(+cap: Nat, +it: S.Item) -> Type:
  {Nat.is_le(Laws.rsize(D2.item.rec(it)), cap) == True{} : Bool}
    -> Pair({Laws.item.from(it) == 1 : U32},
      {Laws.item.upto(it) == U32.from_nat(D2.rec.count(D2.item.rec(it))) : U32})

# every item of an open shard is okit
def okg(+cap: Nat, g: S.Open) -> Type:
  M1.All(S.Item, it => okit(cap, it), M1.open.items(g))

# a whole record is okit
def whole_ok(+cap: Nat, rec: R.Record) -> okit(cap, S.Shard.whole(rec)):
  match rec:
    case R.Record{_id, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
      _h => ({==}, {==})

# a piece of a record that does not fit is okit
def piece_ok(
  +cap: Nat,
  +rec: R.Record,
  -j: Nat,
  -m: Nat,
  nb: {Nat.is_le(Laws.rsize(rec), cap) == False{} : Bool}
) -> okit(cap, S.Shard.piece(rec, j, m)):
  h => Empty.absurd(Pair({U32.from_nat(1n+j) == 1 : U32},
    {U32.from_nat(1n+Nat.add(j, m)) == U32.from_nat(D2.rec.count(rec)) : U32}),
    M2.clash(Equal.trans(Bool, False{}, Nat.is_le(Laws.rsize(rec), cap), True{},
      Equal.sym(Bool, Nat.is_le(Laws.rsize(rec), cap), False{}, nb), h)))

# okg of a step after the next paragraph joined the piece or not
def cut_whole.if(
  b: Bool,
  +cap: Nat,
  +rec: R.Record,
  -h: Nat,
  +j: Nat,
  +m: Nat,
  -sz: Nat,
  st: S.Step,
  nb: {Nat.is_le(Laws.rsize(rec), cap) == False{} : Bool},
  ih: M1.StepAll(g => okg(cap, g), st)
) -> M1.StepAll(g => okg(cap, g), S.Shard.cut.if(b, rec, h, j, m, sz, st)):
  match b:
    case True{}:
      ih
    case False{}:
      M1.emit_all(g => okg(cap, g), S.Open{[S.Shard.piece(rec, j, m)], Nat.add(h, sz)},
        st, (piece_ok(cap, rec, j, m, nb), Unit{}), ih)

# the pieces of a record that does not fit are okit
def cut_whole(
  ps: List<&2, P.Para>,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  +nb: {Nat.is_le(Laws.rsize(rec), cap) == False{} : Bool}
) -> M1.StepAll(g => okg(cap, g), S.Shard.cut(ps, cap, rec, h, j, m, sz)):
  match ps:
    case Nil{}:
      (Unit{}, (piece_ok(cap, rec, j, m, nb), Unit{}))
    case Con{pa, +rest}:
      match pa:
        case P.Para{_n, _start, _end, +text}:
          cut_whole.if(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap),
            cap, rec, h, j, m, sz,
            S.Shard.cut(rest, cap, rec, h,
              S.Shard.cut.j(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), j, m),
              S.Shard.cut.m(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), m),
              S.Shard.cut.sz(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), sz,
                String.length(text))),
            nb,
            cut_whole(rest, cap, rec, h,
              S.Shard.cut.j(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), j, m),
              S.Shard.cut.m(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), m),
              S.Shard.cut.sz(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), sz,
                String.length(text)), nb))

# a record cut at paragraph boundaries: okg, when it does not fit
def split_whole(
  rec: R.Record,
  +cap: Nat,
  nb: {Nat.is_le(Laws.rsize(rec), cap) == False{} : Bool}
) -> M1.StepAll(g => okg(cap, g),
  S.Shard.split(S.Shard.paras(rec), cap, rec, R.Record.size(rec))):
  match rec:
    case R.Record{+id, +ts, +source, +author, +thread, +parent, paras, +ptr}:
      match paras:
        case Nil{}:
          (Unit{}, (whole_ok(cap, R.Record{id, ts, source, author, thread, parent,
            [], ptr}), Unit{}))
        case Con{pa, +rest}:
          match pa:
            case P.Para{+pn, +pstart, +pend, +text}:
              cut_whole(rest, cap, R.Record{id, ts, source, author, thread, parent,
                P.Para{pn, pstart, pend, text} <> rest, ptr},
                String.length(R.Record.header(R.Record{id, ts, source, author,
                  thread, parent, P.Para{pn, pstart, pend, text} <> rest, ptr})),
                0n, 0n, String.length(text), nb)

# a record whole or cut on an empty shard: okg
def lay_whole(
  small: Bool,
  +cap: Nat,
  +rec: R.Record,
  e: {Nat.is_le(R.Record.size(rec), cap) == small : Bool}
) -> M1.StepAll(g => okg(cap, g), S.Shard.lay.if(small, cap, rec, R.Record.size(rec))):
  match small:
    case True{}:
      (Unit{}, (whole_ok(cap, rec), Unit{}))
    case False{}:
      split_whole(rec, cap,
        Equal.trans(Bool, Nat.is_le(Laws.rsize(rec), cap),
          Nat.is_le(R.Record.size(rec), cap), False{},
          Equal.cong(Nat, Bool, x => Nat.is_le(x, cap), Laws.rsize(rec),
            R.Record.size(rec), Equal.sym(Nat, R.Record.size(rec), Laws.rsize(rec),
              M1.size_same(rec))), e))

# a step from an okg open shard: okg
def step_whole.if(
  fits: Bool,
  +cap: Nat,
  +cur: List<&2, S.Item>,
  +size: Nat,
  +rec: R.Record,
  hcur: M1.All(S.Item, it => okit(cap, it), cur)
) -> M1.StepAll(g => okg(cap, g),
  S.Shard.step.if(fits, cap, cur, size, rec, R.Record.size(rec))):
  match fits:
    case True{}:
      (Unit{}, M1.all_app(S.Item, it => okit(cap, it), cur, [S.Shard.whole(rec)], hcur,
        (whole_ok(cap, rec), Unit{})))
    case False{}:
      M1.after_all(g => okg(cap, g), S.Shard.shut(cur, size),
        S.Shard.lay.if(Nat.is_le(R.Record.size(rec), cap), cap, rec, R.Record.size(rec)),
        M1.shut_all(g => okg(cap, g), cur, size, hcur),
        lay_whole(Nat.is_le(R.Record.size(rec), cap), cap, rec, {==}))

# a step from an okg open shard: okg
def step_whole(
  +cap: Nat,
  st: S.Open,
  +rec: R.Record,
  hst: okg(cap, st)
) -> M1.StepAll(g => okg(cap, g), S.Shard.step(cap, st, rec)):
  match st:
    case S.Open{+cur, +size}:
      step_whole.if(Nat.is_le(Nat.add(size, R.Record.size(rec)), cap), cap, cur, size,
        rec, hst)

# every shard packing gives is okg
def run_whole(
  xs: List<&2, R.Record>,
  +cap: Nat,
  +st: S.Open,
  hst: okg(cap, st)
) -> M1.All(S.Open, g => okg(cap, g), S.Shard.run(xs, cap, st)):
  match xs:
    case Nil{}:
      (hst, Unit{})
    case Con{+rec, +rest}:
      M1.then_all(g => okg(cap, g), S.Shard.step(cap, st, rec), rest, cap,
        step_whole(cap, st, rec, hst), o => ho => run_whole(rest, cap, o, ho))

# laws/RecordsSplitOnlyWhenTooBig.bend of a made shard
def whole_made(
  +cap: Nat,
  -k: U32,
  g: S.Open,
  -f: Bool,
  -it: S.Item,
  hi: D1.Elem(S.Item, it, D2.shard.items(S.Shard.make(k, g, f))),
  okgg: okg(cap, g)
) -> okit(cap, it):
  match g:
    case S.Open{items, _size}:
      M1.all_elem(S.Item, i => okit(cap, i), items, it, okgg, hi)

# laws/RecordsSplitOnlyWhenTooBig.bend of a shard made of one of gs
def whole_in(
  gs: List<&2, S.Open>,
  +cap: Nat,
  -s: S.Shard,
  -it: S.Item,
  hi: D1.Elem(S.Item, it, D2.shard.items(s)),
  oks: M1.All(S.Open, g => okg(cap, g), gs),
  m: M1.made_in(gs, s)
) -> okit(cap, it):
  match m:
    case (g, (k, (f, (el, e)))):
      whole_made(cap, k, g, f, it,
        (%e : D1.Elem(S.Item, it, D2.shard.items(_)); hi),
        M1.all_elem(S.Open, g2 => okg(cap, g2), gs, g, oks, el))

# laws/RecordsSplitOnlyWhenTooBig.bend: an item of a record that fits is the whole record
def Laws.shard_whole(cap, n, xs, s, hs, it, hi, small):
  +c = U32.to_nat(cap)
  +gs = S.Shard.run(xs, c, S.Open{[], 0n})
  whole_in(gs, c, s, it, hi, run_whole(xs, c, S.Open{[], 0n}, Unit{}),
    M1.number_elem(gs, n, s, hs))(small)
