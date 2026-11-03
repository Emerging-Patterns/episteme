# proofs of laws/ShardsCoverEveryParagraph.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/ShardsCoverEveryParagraph.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/NatArithmetic.bend as M2
import ./lemmas/OffsetsHeld.bend as M3
import ./lemmas/PackingSteps.bend as M4
import ./lemmas/PieceParagraphs.bend as M5

# the pairs of a ++ b
def pairs_app(
  +r: R.Record,
  a: List<&2, P.Para>,
  -b: List<&2, P.Para>
) -> {D1.pairs(r, List.append(&2, P.Para, a, b)) == List.append(&2, S.Shard.Line(), D1.pairs(r, a), D1.pairs(r,
  b)) : List<&2, S.Shard.Line()>}:
  match a:
    case Nil{}:
      {==}
    case Con{+h, t}:
      Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>, x => (r, h) <> x,
        D1.pairs(r, List.append(&2, P.Para, t, b)),
        List.append(&2, S.Shard.Line(), D1.pairs(r, t), D1.pairs(r, b)),
        pairs_app(r, t, b))

# the cover of the items a ++ b
law icover_app:
  for a: List<&2, S.Item>
  for +b: List<&2, S.Item>
  {D1.items.cover(List.append(&2, S.Item, a, b))
    == List.append(&2, S.Shard.Line(), D1.items.cover(a), D1.items.cover(b))
    : List<&2, S.Shard.Line()>}

def icover_app(a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+it, +t}:
      Equal.trans(List<&2, S.Shard.Line()>,
        List.append(&2, S.Shard.Line(), D1.pairs(D1.item.rec(it), D1.item.paras(it)),
          D1.items.cover(List.append(&2, S.Item, t, b))),
        List.append(&2, S.Shard.Line(), D1.pairs(D1.item.rec(it), D1.item.paras(it)),
          List.append(&2, S.Shard.Line(), D1.items.cover(t), D1.items.cover(b))),
        List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(),
          D1.pairs(D1.item.rec(it), D1.item.paras(it)), D1.items.cover(t)),
          D1.items.cover(b)),
        Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
          x => List.append(&2, S.Shard.Line(),
            D1.pairs(D1.item.rec(it), D1.item.paras(it)), x),
          D1.items.cover(List.append(&2, S.Item, t, b)),
          List.append(&2, S.Shard.Line(), D1.items.cover(t), D1.items.cover(b)),
          icover_app(t, b)),
        Equal.sym(List<&2, S.Shard.Line()>,
          List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(),
            D1.pairs(D1.item.rec(it), D1.item.paras(it)), D1.items.cover(t)),
            D1.items.cover(b)),
          List.append(&2, S.Shard.Line(), D1.pairs(D1.item.rec(it), D1.item.paras(it)),
            List.append(&2, S.Shard.Line(), D1.items.cover(t), D1.items.cover(b))),
          M4.lapp_assoc(S.Shard.Line(), D1.pairs(D1.item.rec(it), D1.item.paras(it)),
            D1.items.cover(t), D1.items.cover(b))))

# the paragraphs open shards hold, in order, each beside its record
def gcover(gs: List<&2, S.Open>) -> List<&2, S.Shard.Line()>:
  match gs:
    case Nil{}:
      []
    case Con{g, rest}:
      List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(g)), gcover(rest))

# the cover of a ++ b
law gcover_app:
  for a: List<&2, S.Open>
  for +b: List<&2, S.Open>
  {gcover(List.append(&2, S.Open, a, b))
    == List.append(&2, S.Shard.Line(), gcover(a), gcover(b)) : List<&2, S.Shard.Line()>}

def gcover_app(a, b):
  match a:
    case Nil{}:
      {==}
    case Con{+g, +t}:
      Equal.trans(List<&2, S.Shard.Line()>,
        List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(g)),
          gcover(List.append(&2, S.Open, t, b))),
        List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(g)),
          List.append(&2, S.Shard.Line(), gcover(t), gcover(b))),
        List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(),
          D1.items.cover(M1.open.items(g)), gcover(t)), gcover(b)),
        Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
          x => List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(g)), x),
          gcover(List.append(&2, S.Open, t, b)),
          List.append(&2, S.Shard.Line(), gcover(t), gcover(b)), gcover_app(t, b)),
        Equal.sym(List<&2, S.Shard.Line()>,
          List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(),
            D1.items.cover(M1.open.items(g)), gcover(t)), gcover(b)),
          List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(g)),
            List.append(&2, S.Shard.Line(), gcover(t), gcover(b))),
          M4.lapp_assoc(S.Shard.Line(), D1.items.cover(M1.open.items(g)), gcover(t),
            gcover(b))))

# a step's frozen shards and then its open one cover x
def covstep(t: S.Step, x: List<&2, S.Shard.Line()>) -> Type:
  match t:
    case S.Step{out, next}:
      {List.append(&2, S.Shard.Line(), gcover(out), D1.items.cover(M1.open.items(next)))
        == x : List<&2, S.Shard.Line()>}

# covstep of a shard frozen ahead of a step
def emit_cov(
  +o: S.Open,
  t: S.Step,
  -y: List<&2, S.Shard.Line()>,
  h: covstep(t, y)
) -> covstep(S.Shard.emit(o, t),
  List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(o)), y)):
  match t:
    case S.Step{+out, +next}:
      Equal.trans(List<&2, S.Shard.Line()>,
        List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(),
          D1.items.cover(M1.open.items(o)), gcover(out)), D1.items.cover(M1.open.items(next))),
        List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(o)),
          List.append(&2, S.Shard.Line(), gcover(out), D1.items.cover(M1.open.items(next)))),
        List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(o)), y),
        M4.lapp_assoc(S.Shard.Line(), D1.items.cover(M1.open.items(o)), gcover(out),
          D1.items.cover(M1.open.items(next))),
        Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
          z => List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(o)), z),
          List.append(&2, S.Shard.Line(), gcover(out), D1.items.cover(M1.open.items(next))),
          y, h))

# covstep of shards frozen ahead of a step
def after_cov(
  +out: List<&2, S.Open>,
  t: S.Step,
  -y: List<&2, S.Shard.Line()>,
  h: covstep(t, y)
) -> covstep(S.Shard.after(out, t), List.append(&2, S.Shard.Line(), gcover(out), y)):
  match t:
    case S.Step{+more, +next}:
      %Equal.sym(List<&2, S.Shard.Line()>, gcover(List.append(&2, S.Open, out, more)),
        List.append(&2, S.Shard.Line(), gcover(out), gcover(more)), gcover_app(out, more))
        : {List.append(&2, S.Shard.Line(), _, D1.items.cover(M1.open.items(next)))
          == List.append(&2, S.Shard.Line(), gcover(out), y) : List<&2, S.Shard.Line()>}
      Equal.trans(List<&2, S.Shard.Line()>,
        List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(), gcover(out),
          gcover(more)), D1.items.cover(M1.open.items(next))),
        List.append(&2, S.Shard.Line(), gcover(out),
          List.append(&2, S.Shard.Line(), gcover(more), D1.items.cover(M1.open.items(next)))),
        List.append(&2, S.Shard.Line(), gcover(out), y),
        M4.lapp_assoc(S.Shard.Line(), gcover(out), gcover(more),
          D1.items.cover(M1.open.items(next))),
        Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
          z => List.append(&2, S.Shard.Line(), gcover(out), z),
          List.append(&2, S.Shard.Line(), gcover(more), D1.items.cover(M1.open.items(next))),
          y, h))

# the open shard, frozen, covers what it held
def shut_cov(
  cur: List<&2, S.Item>,
  -size: Nat
) -> {gcover(S.Shard.shut(cur, size)) == D1.items.cover(cur) : List<&2, S.Shard.Line()>}:
  match cur:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      M3.lapp_nil(S.Shard.Line(), D1.items.cover(h <> t))

# a piece covers its paragraphs
def piece_cov(
  +rec: R.Record,
  +j: Nat,
  +m: Nat,
  +acc: List<&2, P.Para>,
  +rest: List<&2, P.Para>,
  hd: {List.drop(&2, P.Para, D1.rec.paras(rec), j) == List.append(&2, P.Para, acc, rest) : List<&2, P.Para>},
  hl: {List.length(&2, P.Para, acc) == 1n+m : Nat},
  hr: M2.rt(1n+Nat.add(j, m))
) -> {D1.items.cover([S.Shard.piece(rec, j, m)]) == D1.pairs(rec, acc) : List<&2, S.Shard.Line()>}:
  Equal.trans(List<&2, S.Shard.Line()>,
    D1.items.cover([S.Shard.piece(rec, j, m)]),
    D1.pairs(rec, D1.item.paras(S.Shard.piece(rec, j, m))),
    D1.pairs(rec, acc),
    M3.lapp_nil(S.Shard.Line(), D1.pairs(rec, D1.item.paras(S.Shard.piece(rec, j, m)))),
    Equal.cong(List<&2, P.Para>, List<&2, S.Shard.Line()>, x => D1.pairs(rec, x),
      D1.item.paras(S.Shard.piece(rec, j, m)), acc,
      M5.piece_paras(rec, j, m, acc, rest, hd, hl, hr)))

# a whole record covers its paragraphs
def whole_cov(
  +rec: R.Record,
  hr: M2.rt(D1.rec.count(rec))
) -> {D1.items.cover([S.Shard.whole(rec)]) == D1.pairs(rec, D1.rec.paras(rec)) : List<&2, S.Shard.Line()>}:
  Equal.trans(List<&2, S.Shard.Line()>,
    D1.items.cover([S.Shard.whole(rec)]),
    D1.pairs(rec, D1.item.paras(S.Shard.whole(rec))),
    D1.pairs(rec, D1.rec.paras(rec)),
    M3.lapp_nil(S.Shard.Line(), D1.pairs(rec, D1.item.paras(S.Shard.whole(rec)))),
    Equal.cong(List<&2, P.Para>, List<&2, S.Shard.Line()>, x => D1.pairs(rec, x),
      D1.item.paras(S.Shard.whole(rec)), D1.rec.paras(rec), M5.whole_paras(rec, hr)))

# what cut_cov gives for the rest, after the next paragraph joined the piece
# or not
def cut_cov.ih(
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
    -> M2.rt(Nat.add(Nat.add(S.Shard.cut.j(b, j, m), 1n+S.Shard.cut.m(b, m)),
      List.length(&2, P.Para, rest)))
    -> covstep(S.Shard.cut(rest, cap, rec, h, S.Shard.cut.j(b, j, m), S.Shard.cut.m(b, m),
      S.Shard.cut.sz(b, sz, l)), D1.pairs(rec, List.append(&2, P.Para, acc2, rest)))

# covstep after the next paragraph joined the piece or not
def cut_cov.if(
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
  +hd: {List.drop(&2, P.Para, D1.rec.paras(rec), j) == List.append(&2, P.Para, acc, pa <> rest) : List<&2, P.Para>},
  +hl: {List.length(&2, P.Para, acc) == 1n+m : Nat},
  +hr: M5.rtd(Nat.add(Nat.add(j, 1n+m), 1n+List.length(&2, P.Para, rest))),
  ih: cut_cov.ih(b, cap, rec, h, j, m, sz, l, rest)
) -> covstep(S.Shard.cut.if(b, rec, h, j, m, sz, S.Shard.cut(rest, cap, rec, h, S.Shard.cut.j(b, j, m),
  S.Shard.cut.m(b, m), S.Shard.cut.sz(b, sz, l))), D1.pairs(rec, List.append(&2, P.Para, acc, pa <> rest))):
  match b:
    case True{}:
      %M4.lapp_assoc(P.Para, acc, [pa], rest)
        : covstep(S.Shard.cut(rest, cap, rec, h, j, 1n+m, Nat.add(sz, l)),
          D1.pairs(rec, _))
      ih(List.append(&2, P.Para, acc, [pa]),
        M5.join_hd(D1.rec.paras(rec), j, acc, pa, rest, hd), M5.join_hl(acc, pa, m, hl),
        M5.join_hr(j, m, List.length(&2, P.Para, rest), hr))
    case False{}:
      %Equal.trans(List<&2, S.Shard.Line()>,
        List.append(&2, S.Shard.Line(), D1.items.cover([S.Shard.piece(rec, j, m)]),
          D1.pairs(rec, pa <> rest)),
        List.append(&2, S.Shard.Line(), D1.pairs(rec, acc), D1.pairs(rec, pa <> rest)),
        D1.pairs(rec, List.append(&2, P.Para, acc, pa <> rest)),
        Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
          z => List.append(&2, S.Shard.Line(), z, D1.pairs(rec, pa <> rest)),
          D1.items.cover([S.Shard.piece(rec, j, m)]), D1.pairs(rec, acc),
          piece_cov(rec, j, m, acc, pa <> rest, hd, hl,
            M5.piece_rt(j, m, 1n+List.length(&2, P.Para, rest), hr))),
        Equal.sym(List<&2, S.Shard.Line()>, D1.pairs(rec, List.append(&2, P.Para, acc, pa <> rest)),
          List.append(&2, S.Shard.Line(), D1.pairs(rec, acc), D1.pairs(rec, pa <> rest)),
          pairs_app(rec, acc, pa <> rest)))
        : covstep(S.Shard.emit(S.Open{[S.Shard.piece(rec, j, m)], Nat.add(h, sz)},
          S.Shard.cut(rest, cap, rec, h, Nat.add(j, 1n+m), 0n, l)), _)
      emit_cov(S.Open{[S.Shard.piece(rec, j, m)], Nat.add(h, sz)},
        S.Shard.cut(rest, cap, rec, h, Nat.add(j, 1n+m), 0n, l),
        D1.pairs(rec, pa <> rest),
        ih([pa], M5.emit_hd(D1.rec.paras(rec), j, m, acc, pa, rest, hd, hl), {==},
          M5.emit_hr(j, m, List.length(&2, P.Para, rest), hr)))

# the pieces cut from ps after the piece being built cover its paragraphs
# and ps
def cut_cov(
  ps: List<&2, P.Para>,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  +acc: List<&2, P.Para>,
  +hd: {List.drop(&2, P.Para, D1.rec.paras(rec), j) == List.append(&2, P.Para, acc, ps) : List<&2, P.Para>},
  +hl: {List.length(&2, P.Para, acc) == 1n+m : Nat},
  +hr: M5.rtd(Nat.add(Nat.add(j, 1n+m), List.length(&2, P.Para, ps)))
) -> covstep(S.Shard.cut(ps, cap, rec, h, j, m, sz), D1.pairs(rec, List.append(&2, P.Para, acc, ps))):
  match ps:
    case Nil{}:
      Equal.trans(List<&2, S.Shard.Line()>, D1.items.cover([S.Shard.piece(rec, j, m)]),
        D1.pairs(rec, acc), D1.pairs(rec, List.append(&2, P.Para, acc, [])),
        piece_cov(rec, j, m, acc, [], hd, hl, M5.piece_rt(j, m, 0n, hr)),
        Equal.sym(List<&2, S.Shard.Line()>, D1.pairs(rec, List.append(&2, P.Para, acc, [])),
          D1.pairs(rec, acc),
          Equal.cong(List<&2, P.Para>, List<&2, S.Shard.Line()>, x => D1.pairs(rec, x),
            List.append(&2, P.Para, acc, []), acc, M3.lapp_nil(P.Para, acc))))
    case Con{pa, +rest}:
      match pa:
        case P.Para{+pn, +pstart, +pend, +text}:
          cut_cov.if(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap),
            cap, rec, h, j, m, sz, P.Para{pn, pstart, pend, text}, String.length(text),
            rest, acc, hd, hl, hr,
            acc2 => hd2 => hl2 => hr2 => cut_cov(rest, cap, rec, h,
              S.Shard.cut.j(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), j, m),
              S.Shard.cut.m(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), m),
              S.Shard.cut.sz(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), sz,
                String.length(text)), acc2, hd2, hl2, hr2))

# a record cut at paragraph boundaries covers its paragraphs
def split_cov(
  rec: R.Record,
  +cap: Nat,
  hr: M2.rt(D1.rec.count(rec))
) -> covstep(S.Shard.split(S.Shard.paras(rec), cap, rec, R.Record.size(rec)), D1.pairs(rec, D1.rec.paras(rec))):
  match rec:
    case R.Record{+id, +ts, +source, +author, +thread, +parent, paras, +ptr}:
      match paras:
        case Nil{}:
          whole_cov(R.Record{id, ts, source, author, thread, parent, [], ptr}, hr)
        case Con{pa, +rest}:
          match pa:
            case P.Para{+pn, +pstart, +pend, +text}:
              cut_cov(rest, cap, R.Record{id, ts, source, author, thread, parent,
                P.Para{pn, pstart, pend, text} <> rest, ptr},
                String.length(R.Record.header(R.Record{id, ts, source, author,
                  thread, parent, P.Para{pn, pstart, pend, text} <> rest, ptr})),
                0n, 0n, String.length(text), [P.Para{pn, pstart, pend, text}], {==}, {==}, hr)

# a record whole or cut on an empty shard covers its paragraphs
def lay_cov(
  small: Bool,
  +cap: Nat,
  +rec: R.Record,
  hr: M2.rt(D1.rec.count(rec))
) -> covstep(S.Shard.lay.if(small, cap, rec, R.Record.size(rec)), D1.pairs(rec, D1.rec.paras(rec))):
  match small:
    case True{}:
      whole_cov(rec, hr)
    case False{}:
      split_cov(rec, cap, hr)

# a step covers the open shard's paragraphs and then the record's
def step_cov.if(
  fits: Bool,
  +cap: Nat,
  +cur: List<&2, S.Item>,
  +size: Nat,
  +rec: R.Record,
  +hr: {U32.to_nat(U32.from_nat(D1.rec.count(rec))) == D1.rec.count(rec) : Nat}
) -> covstep(S.Shard.step.if(fits, cap, cur, size, rec, R.Record.size(rec)),
  List.append(&2, S.Shard.Line(), D1.items.cover(cur), D1.pairs(rec, D1.rec.paras(rec)))):
  match fits:
    case True{}:
      Equal.trans(List<&2, S.Shard.Line()>,
        D1.items.cover(List.append(&2, S.Item, cur, [S.Shard.whole(rec)])),
        List.append(&2, S.Shard.Line(), D1.items.cover(cur), D1.items.cover([S.Shard.whole(rec)])),
        List.append(&2, S.Shard.Line(), D1.items.cover(cur), D1.pairs(rec, D1.rec.paras(rec))),
        icover_app(cur, [S.Shard.whole(rec)]),
        Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
          z => List.append(&2, S.Shard.Line(), D1.items.cover(cur), z),
          D1.items.cover([S.Shard.whole(rec)]), D1.pairs(rec, D1.rec.paras(rec)),
          whole_cov(rec, hr)))
    case False{}:
      %Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
        z => List.append(&2, S.Shard.Line(), z, D1.pairs(rec, D1.rec.paras(rec))),
        gcover(S.Shard.shut(cur, size)), D1.items.cover(cur), shut_cov(cur, size))
        : covstep(S.Shard.after(S.Shard.shut(cur, size),
          S.Shard.lay.if(Nat.is_le(R.Record.size(rec), cap), cap, rec, R.Record.size(rec))), _)
      after_cov(S.Shard.shut(cur, size),
        S.Shard.lay.if(Nat.is_le(R.Record.size(rec), cap), cap, rec, R.Record.size(rec)),
        D1.pairs(rec, D1.rec.paras(rec)),
        lay_cov(Nat.is_le(R.Record.size(rec), cap), cap, rec, hr))

# a step covers the open shard's paragraphs and then the record's
def step_cov(
  +cap: Nat,
  st: S.Open,
  +rec: R.Record,
  +hr: {U32.to_nat(U32.from_nat(D1.rec.count(rec))) == D1.rec.count(rec) : Nat}
) -> covstep(S.Shard.step(cap, st, rec), List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(st)),
  D1.pairs(rec, D1.rec.paras(rec)))):
  match st:
    case S.Open{+cur, +size}:
      step_cov.if(Nat.is_le(Nat.add(size, R.Record.size(rec)), cap), cap, cur, size,
        rec, hr)

# what run_cov gives for the rest, from any open shard
def run_cov.ih(+rest: List<&2, R.Record>, +cap: Nat) -> Type:
  @o: S.Open -> {gcover(S.Shard.run(rest, cap, o))
    == List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(o)), D1.cover(rest))
    : List<&2, S.Shard.Line()>}

# a step's cover, then what the rest packs
def run_cov.then(
  t: S.Step,
  +rest: List<&2, R.Record>,
  +cap: Nat,
  +x: List<&2, S.Shard.Line()>,
  +y: List<&2, S.Shard.Line()>,
  h: covstep(t, List.append(&2, S.Shard.Line(), x, y)),
  ih: run_cov.ih(rest, cap)
) -> {gcover(S.Shard.then(t, o => S.Shard.run(rest, cap, o))) == List.append(&2, S.Shard.Line(), x, List.append(&2,
  S.Shard.Line(), y, D1.cover(rest))) : List<&2, S.Shard.Line()>}:
  match t:
    case S.Step{+out, +next}:
      Equal.trans(List<&2, S.Shard.Line()>,
        gcover(List.append(&2, S.Open, out, S.Shard.run(rest, cap, next))),
        List.append(&2, S.Shard.Line(), gcover(out), gcover(S.Shard.run(rest, cap, next))),
        List.append(&2, S.Shard.Line(), x, List.append(&2, S.Shard.Line(), y, D1.cover(rest))),
        gcover_app(out, S.Shard.run(rest, cap, next)),
        (%Equal.sym(List<&2, S.Shard.Line()>, gcover(S.Shard.run(rest, cap, next)),
          List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(next)), D1.cover(rest)),
          ih(next))
          : {List.append(&2, S.Shard.Line(), gcover(out), _)
            == List.append(&2, S.Shard.Line(), x, List.append(&2, S.Shard.Line(), y, D1.cover(rest)))
            : List<&2, S.Shard.Line()>}
        Equal.trans(List<&2, S.Shard.Line()>,
          List.append(&2, S.Shard.Line(), gcover(out),
            List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(next)), D1.cover(rest))),
          List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(), gcover(out),
            D1.items.cover(M1.open.items(next))), D1.cover(rest)),
          List.append(&2, S.Shard.Line(), x, List.append(&2, S.Shard.Line(), y, D1.cover(rest))),
          Equal.sym(List<&2, S.Shard.Line()>,
            List.append(&2, S.Shard.Line(), List.append(&2, S.Shard.Line(), gcover(out),
              D1.items.cover(M1.open.items(next))), D1.cover(rest)),
            List.append(&2, S.Shard.Line(), gcover(out),
              List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(next)), D1.cover(rest))),
            M4.lapp_assoc(S.Shard.Line(), gcover(out), D1.items.cover(M1.open.items(next)),
              D1.cover(rest))),
          (%Equal.sym(List<&2, S.Shard.Line()>,
            List.append(&2, S.Shard.Line(), gcover(out), D1.items.cover(M1.open.items(next))),
            List.append(&2, S.Shard.Line(), x, y), h)
            : {List.append(&2, S.Shard.Line(), _, D1.cover(rest))
              == List.append(&2, S.Shard.Line(), x, List.append(&2, S.Shard.Line(), y, D1.cover(rest)))
              : List<&2, S.Shard.Line()>}
          M4.lapp_assoc(S.Shard.Line(), x, y, D1.cover(rest))))))

# packing covers the open shard's paragraphs and then the records'
def run_cov(
  xs: List<&2, R.Record>,
  +cap: Nat,
  +st: S.Open,
  hc: D1.counted(xs)
) -> {gcover(S.Shard.run(xs, cap, st)) == List.append(&2, S.Shard.Line(), D1.items.cover(M1.open.items(st)),
  D1.cover(xs)) : List<&2, S.Shard.Line()>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+rec, +rest}:
      match hc:
        case (hr, hrest):
          run_cov.then(S.Shard.step(cap, st, rec), rest, cap,
            D1.items.cover(M1.open.items(st)), D1.pairs(rec, D1.rec.paras(rec)),
            step_cov(cap, st, rec, hr), o => run_cov(rest, cap, o, hrest))

# numbered shards cover what the open shards did
def num_cov(
  gs: List<&2, S.Open>,
  +n: U32
) -> {Laws.shards.cover(S.Shard.number(gs, n)) == gcover(gs) : List<&2, S.Shard.Line()>}:
  match gs:
    case Nil{}:
      {==}
    case Con{g, +rest}:
      match g:
        case S.Open{+items, _size}:
          Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
            z => List.append(&2, S.Shard.Line(), D1.items.cover(items), z),
            Laws.shards.cover(S.Shard.number(rest, U32.inc(n))), gcover(rest),
            num_cov(rest, U32.inc(n)))

# laws/ShardsCoverEveryParagraph.bend: the shards hold every paragraph once, in order
def Laws.shard_cover(cap, n, xs, h):
  +c = U32.to_nat(cap)
  Equal.trans(List<&2, S.Shard.Line()>, Laws.shards.cover(S.Shard.pack(cap, n, xs)),
    gcover(S.Shard.run(xs, c, S.Open{[], 0n})), D1.cover(xs),
    num_cov(S.Shard.run(xs, c, S.Open{[], 0n}), n),
    run_cov(xs, c, S.Open{[], 0n}, h))
