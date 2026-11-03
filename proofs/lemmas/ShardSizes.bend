# the size of every shard packing gives
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../laws/RecordsSplitOnlyWhenTooBig.bend as L1
import ../../laws/defs/Specification.bend as D1
import ./AllOfShards.bend as M1
import ./NatArithmetic.bend as M2
import ./PieceParagraphs.bend as M3

# an open shard's size
def open.size(g: S.Open) -> Nat:
  match g:
    case S.Open{_items, size}:
      size

# the text count of acc ++ b
law texts_app:
  for acc: List<&2, P.Para>
  for +b: List<&2, P.Para>
  {D1.texts(List.append(&2, P.Para, acc, b))
    == Nat.add(D1.texts(acc), D1.texts(b)) : Nat}

def texts_app(acc, b):
  match acc:
    case Nil{}:
      {==}
    case Con{pa, +t}:
      match pa:
        case P.Para{_n, _start, _end, +text}:
          Equal.trans(Nat,
            Nat.add(String.length(text), D1.texts(List.append(&2, P.Para, t, b))),
            Nat.add(String.length(text), Nat.add(D1.texts(t), D1.texts(b))),
            Nat.add(Nat.add(String.length(text), D1.texts(t)), D1.texts(b)),
            Equal.cong(Nat, Nat, x => Nat.add(String.length(text), x),
              D1.texts(List.append(&2, P.Para, t, b)),
              Nat.add(D1.texts(t), D1.texts(b)), texts_app(t, b)),
            Equal.sym(Nat, Nat.add(Nat.add(String.length(text), D1.texts(t)), D1.texts(b)),
              Nat.add(String.length(text), Nat.add(D1.texts(t), D1.texts(b))),
              M2.add_assoc(String.length(text), D1.texts(t), D1.texts(b))))

# the size of a ++ b
law size_app:
  for a: List<&2, S.Item>
  for +b: List<&2, S.Item>
  {D1.size(List.append(&2, S.Item, a, b)) == Nat.add(D1.size(a), D1.size(b)) : Nat}

def size_app(a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+it, +t}:
      Equal.trans(Nat,
        Nat.add(D1.item.size(it), D1.size(List.append(&2, S.Item, t, b))),
        Nat.add(D1.item.size(it), Nat.add(D1.size(t), D1.size(b))),
        Nat.add(Nat.add(D1.item.size(it), D1.size(t)), D1.size(b)),
        Equal.cong(Nat, Nat, x => Nat.add(D1.item.size(it), x),
          D1.size(List.append(&2, S.Item, t, b)),
          Nat.add(D1.size(t), D1.size(b)), size_app(t, b)),
        Equal.sym(Nat, Nat.add(Nat.add(D1.item.size(it), D1.size(t)), D1.size(b)),
          Nat.add(D1.item.size(it), Nat.add(D1.size(t), D1.size(b))),
          M2.add_assoc(D1.item.size(it), D1.size(t), D1.size(b))))

# an open shard's size is its items' size
def szeq(g: S.Open) -> Type:
  {D1.size(M1.open.items(g)) == open.size(g) : Nat}

# a piece's size is its header line and its paragraphs' text
def piece_sz(
  +rec: R.Record,
  +j: Nat,
  +m: Nat,
  +acc: List<&2, P.Para>,
  +rest: List<&2, P.Para>,
  +h: Nat,
  +sz: Nat,
  hh: {h == D1.rec.head(rec) : Nat},
  hd: {List.drop(&2, P.Para, D1.rec.paras(rec), j) == List.append(&2, P.Para, acc, rest) : List<&2, P.Para>},
  hl: {List.length(&2, P.Para, acc) == 1n+m : Nat},
  hr: M2.rt(1n+Nat.add(j, m)),
  ht: {D1.texts(acc) == sz : Nat}
) -> szeq(S.Open{[S.Shard.piece(rec, j, m)], Nat.add(h, sz)}):
  Equal.trans(Nat, Nat.add(D1.item.size(S.Shard.piece(rec, j, m)), 0n),
    D1.item.size(S.Shard.piece(rec, j, m)), Nat.add(h, sz),
    M2.add_zero_r(D1.item.size(S.Shard.piece(rec, j, m))),
    (%Equal.sym(List<&2, P.Para>, D1.item.paras(S.Shard.piece(rec, j, m)), acc,
      M3.piece_paras(rec, j, m, acc, rest, hd, hl, hr))
      : {Nat.add(D1.rec.head(rec), D1.texts(_)) == Nat.add(h, sz) : Nat}
    %hh : {Nat.add(_, D1.texts(acc)) == Nat.add(h, sz) : Nat}
    Equal.cong(Nat, Nat, x => Nat.add(h, x), D1.texts(acc), sz, ht)))

# a whole record's size is Record.size
def whole_sz(
  +rec: R.Record,
  hr: M2.rt(D1.rec.count(rec))
) -> {D1.size([S.Shard.whole(rec)]) == R.Record.size(rec) : Nat}:
  Equal.trans(Nat, Nat.add(D1.item.size(S.Shard.whole(rec)), 0n),
    D1.item.size(S.Shard.whole(rec)), R.Record.size(rec),
    M2.add_zero_r(D1.item.size(S.Shard.whole(rec))),
    (%Equal.sym(List<&2, P.Para>, D1.item.paras(S.Shard.whole(rec)),
      D1.rec.paras(rec), M3.whole_paras(rec, hr))
      : {Nat.add(D1.rec.head(rec), D1.texts(_)) == R.Record.size(rec) : Nat}
    Equal.sym(Nat, R.Record.size(rec), L1.rsize(rec), M1.size_same(rec))))

# what cut_sz gives for the rest, after the next paragraph joined the piece
# or not
def cut_sz.ih(
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
  @acc2: List<&2, P.Para>
    -> {List.drop(&2, P.Para, D1.rec.paras(rec), S.Shard.cut.j(b, j, m))
      == List.append(&2, P.Para, acc2, rest) : List<&2, P.Para>}
    -> {List.length(&2, P.Para, acc2) == 1n+S.Shard.cut.m(b, m) : Nat}
    -> {D1.texts(acc2) == S.Shard.cut.sz(b, sz, l) : Nat}
    -> M2.rt(Nat.add(Nat.add(S.Shard.cut.j(b, j, m), 1n+S.Shard.cut.m(b, m)),
      List.length(&2, P.Para, rest)))
    -> M1.StepAll(szeq, S.Shard.cut(rest, cap, rec, h, S.Shard.cut.j(b, j, m),
      S.Shard.cut.m(b, m), S.Shard.cut.sz(b, sz, l)))

# szeq after the next paragraph joined the piece or not
def cut_sz.if(
  b: Bool,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  +pa: P.Para,
  +l: Nat,
  +rest: List<&2, P.Para>,
  +acc: List<&2, P.Para>,
  +hh: {h == D1.rec.head(rec) : Nat},
  +hd: {List.drop(&2, P.Para, D1.rec.paras(rec), j) == List.append(&2, P.Para, acc, pa <> rest) : List<&2, P.Para>},
  +hl: {List.length(&2, P.Para, acc) == 1n+m : Nat},
  +ht: {D1.texts(acc) == sz : Nat},
  +hp: {D1.texts([pa]) == l : Nat},
  +hr: M3.rtd(Nat.add(Nat.add(j, 1n+m), 1n+List.length(&2, P.Para, rest))),
  ih: cut_sz.ih(b, cap, rec, h, j, m, sz, l, rest)
) -> M1.StepAll(szeq, S.Shard.cut.if(b, rec, h, j, m, sz, S.Shard.cut(rest, cap, rec, h, S.Shard.cut.j(b, j, m),
  S.Shard.cut.m(b, m), S.Shard.cut.sz(b, sz, l)))):
  match b:
    case True{}:
      ih(List.append(&2, P.Para, acc, [pa]),
        M3.join_hd(D1.rec.paras(rec), j, acc, pa, rest, hd), M3.join_hl(acc, pa, m, hl),
        Equal.trans(Nat, D1.texts(List.append(&2, P.Para, acc, [pa])),
          Nat.add(D1.texts(acc), D1.texts([pa])), Nat.add(sz, l),
          texts_app(acc, [pa]),
          (%Equal.sym(Nat, D1.texts(acc), sz, ht)
            : {Nat.add(_, D1.texts([pa])) == Nat.add(sz, l) : Nat}
          Equal.cong(Nat, Nat, x => Nat.add(sz, x), D1.texts([pa]), l, hp))),
        M3.join_hr(j, m, List.length(&2, P.Para, rest), hr))
    case False{}:
      M1.emit_all(szeq, S.Open{[S.Shard.piece(rec, j, m)], Nat.add(h, sz)},
        S.Shard.cut(rest, cap, rec, h, Nat.add(j, 1n+m), 0n, l),
        piece_sz(rec, j, m, acc, pa <> rest, h, sz, hh, hd, hl,
          M3.piece_rt(j, m, 1n+List.length(&2, P.Para, rest), hr), ht),
        ih([pa], M3.emit_hd(D1.rec.paras(rec), j, m, acc, pa, rest, hd, hl), {==}, hp,
          M3.emit_hr(j, m, List.length(&2, P.Para, rest), hr)))

# every piece cut from ps after the piece being built has its items' size
def cut_sz(
  ps: List<&2, P.Para>,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  +acc: List<&2, P.Para>,
  +hh: {h == D1.rec.head(rec) : Nat},
  +hd: {List.drop(&2, P.Para, D1.rec.paras(rec), j) == List.append(&2, P.Para, acc, ps) : List<&2, P.Para>},
  +hl: {List.length(&2, P.Para, acc) == 1n+m : Nat},
  +ht: {D1.texts(acc) == sz : Nat},
  +hr: M3.rtd(Nat.add(Nat.add(j, 1n+m), List.length(&2, P.Para, ps)))
) -> M1.StepAll(szeq, S.Shard.cut(ps, cap, rec, h, j, m, sz)):
  match ps:
    case Nil{}:
      (Unit{}, piece_sz(rec, j, m, acc, [], h, sz, hh, hd, hl, M3.piece_rt(j, m, 0n, hr), ht))
    case Con{pa, +rest}:
      match pa:
        case P.Para{+pn, +pstart, +pend, +text}:
          cut_sz.if(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap),
            cap, rec, h, j, m, sz, P.Para{pn, pstart, pend, text}, String.length(text),
            rest, acc, hh, hd, hl, ht, M2.add_zero_r(String.length(text)), hr,
            acc2 => hd2 => hl2 => ht2 => hr2 => cut_sz(rest, cap, rec, h,
              S.Shard.cut.j(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), j, m),
              S.Shard.cut.m(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), m),
              S.Shard.cut.sz(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), sz,
                String.length(text)), acc2, hh, hd2, hl2, ht2, hr2))

# every shard a record cut at paragraph boundaries gives has its items' size
def split_sz(
  rec: R.Record,
  +cap: Nat,
  hr: M2.rt(D1.rec.count(rec))
) -> M1.StepAll(szeq, S.Shard.split(S.Shard.paras(rec), cap, rec, R.Record.size(rec))):
  match rec:
    case R.Record{+id, +ts, +source, +author, +thread, +parent, paras, +ptr}:
      match paras:
        case Nil{}:
          (Unit{}, whole_sz(R.Record{id, ts, source, author, thread, parent, [], ptr}, hr))
        case Con{pa, +rest}:
          match pa:
            case P.Para{+pn, +pstart, +pend, +text}:
              cut_sz(rest, cap, R.Record{id, ts, source, author, thread, parent,
                P.Para{pn, pstart, pend, text} <> rest, ptr},
                String.length(R.Record.header(R.Record{id, ts, source, author,
                  thread, parent, P.Para{pn, pstart, pend, text} <> rest, ptr})),
                0n, 0n, String.length(text), [P.Para{pn, pstart, pend, text}], {==},
                {==}, {==}, M2.add_zero_r(String.length(text)), hr)

# every shard a record whole or cut gives has its items' size
def lay_sz(
  small: Bool,
  +cap: Nat,
  +rec: R.Record,
  hr: M2.rt(D1.rec.count(rec))
) -> M1.StepAll(szeq, S.Shard.lay.if(small, cap, rec, R.Record.size(rec))):
  match small:
    case True{}:
      (Unit{}, whole_sz(rec, hr))
    case False{}:
      split_sz(rec, cap, hr)

# every shard a step gives has its items' size
def step_sz.if(
  fits: Bool,
  +cap: Nat,
  +cur: List<&2, S.Item>,
  +size: Nat,
  +rec: R.Record,
  +hr: {U32.to_nat(U32.from_nat(D1.rec.count(rec))) == D1.rec.count(rec) : Nat},
  hst: szeq(S.Open{cur, size})
) -> M1.StepAll(szeq, S.Shard.step.if(fits, cap, cur, size, rec, R.Record.size(rec))):
  match fits:
    case True{}:
      (Unit{}, Equal.trans(Nat,
        D1.size(List.append(&2, S.Item, cur, [S.Shard.whole(rec)])),
        Nat.add(D1.size(cur), D1.size([S.Shard.whole(rec)])),
        Nat.add(size, R.Record.size(rec)),
        size_app(cur, [S.Shard.whole(rec)]),
        (%Equal.sym(Nat, D1.size(cur), size, hst)
          : {Nat.add(_, D1.size([S.Shard.whole(rec)]))
            == Nat.add(size, R.Record.size(rec)) : Nat}
        Equal.cong(Nat, Nat, x => Nat.add(size, x), D1.size([S.Shard.whole(rec)]),
          R.Record.size(rec), whole_sz(rec, hr)))))
    case False{}:
      M1.after_all(szeq, S.Shard.shut(cur, size),
        S.Shard.lay.if(Nat.is_le(R.Record.size(rec), cap), cap, rec, R.Record.size(rec)),
        M1.shut_all(szeq, cur, size, hst),
        lay_sz(Nat.is_le(R.Record.size(rec), cap), cap, rec, hr))

# every shard a step gives has its items' size
def step_sz(
  +cap: Nat,
  st: S.Open,
  +rec: R.Record,
  +hr: {U32.to_nat(U32.from_nat(D1.rec.count(rec))) == D1.rec.count(rec) : Nat},
  hst: szeq(st)
) -> M1.StepAll(szeq, S.Shard.step(cap, st, rec)):
  match st:
    case S.Open{+cur, +size}:
      step_sz.if(Nat.is_le(Nat.add(size, R.Record.size(rec)), cap), cap, cur, size,
        rec, hr, hst)

# every shard packing gives has its items' size
def run_sz(
  xs: List<&2, R.Record>,
  +cap: Nat,
  +st: S.Open,
  hst: szeq(st),
  hc: D1.counted(xs)
) -> M1.All(S.Open, szeq, S.Shard.run(xs, cap, st)):
  match xs:
    case Nil{}:
      (hst, Unit{})
    case Con{+rec, +rest}:
      match hc:
        case (hr, hrest):
          M1.then_all(szeq, S.Shard.step(cap, st, rec), rest, cap,
            step_sz(cap, st, rec, hr, hst), o => ho => run_sz(rest, cap, o, ho, hrest))
