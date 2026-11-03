# proofs of laws/ShardHoldsOneSource.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/ShardHoldsOneSource.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ../laws/defs/Specification.bend as D2
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/BoolFacts.bend as M2

# an item of a record of source src
def srcit(+src: String, it: S.Item) -> Type:
  {Laws.of_src(src, D2.item.rec(it)) == True{} : Bool}

# every item of an open shard is of a record of source src
def srcg(+src: String, g: S.Open) -> Type:
  M1.All(S.Item, it => srcit(src, it), M1.open.items(g))

# a record of source src
def srcr(+src: String, r: R.Record) -> Type:
  {Laws.of_src(src, r) == True{} : Bool}

# srcg of a step after the next paragraph joined the piece or not
def cut_src.if(
  b: Bool,
  +src: String,
  +rec: R.Record,
  -h: Nat,
  +j: Nat,
  +m: Nat,
  -sz: Nat,
  st: S.Step,
  hr: srcr(src, rec),
  ih: M1.StepAll(g => srcg(src, g), st)
) -> M1.StepAll(g => srcg(src, g), S.Shard.cut.if(b, rec, h, j, m, sz, st)):
  match b:
    case True{}:
      ih
    case False{}:
      M1.emit_all(g => srcg(src, g), S.Open{[S.Shard.piece(rec, j, m)], Nat.add(h, sz)},
        st, (hr, Unit{}), ih)

# the pieces of a record of source src are srcg
def cut_src(
  ps: List<&2, P.Para>,
  +src: String,
  +cap: Nat,
  +rec: R.Record,
  +h: Nat,
  +j: Nat,
  +m: Nat,
  +sz: Nat,
  +hr: {Laws.of_src(src, rec) == True{} : Bool}
) -> M1.StepAll(g => srcg(src, g), S.Shard.cut(ps, cap, rec, h, j, m, sz)):
  match ps:
    case Nil{}:
      (Unit{}, (hr, Unit{}))
    case Con{pa, +rest}:
      match pa:
        case P.Para{_n, _start, _end, +text}:
          cut_src.if(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap),
            src, rec, h, j, m, sz,
            S.Shard.cut(rest, cap, rec, h,
              S.Shard.cut.j(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), j, m),
              S.Shard.cut.m(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), m),
              S.Shard.cut.sz(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), sz,
                String.length(text))),
            hr,
            cut_src(rest, src, cap, rec, h,
              S.Shard.cut.j(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), j, m),
              S.Shard.cut.m(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), m),
              S.Shard.cut.sz(Nat.is_le(Nat.add(h, Nat.add(sz, String.length(text))), cap), sz,
                String.length(text)), hr))

# a record of source src cut at paragraph boundaries: srcg
def split_src(
  rec: R.Record,
  +src: String,
  +cap: Nat,
  hr: srcr(src, rec)
) -> M1.StepAll(g => srcg(src, g),
  S.Shard.split(S.Shard.paras(rec), cap, rec, R.Record.size(rec))):
  match rec:
    case R.Record{+id, +ts, +source, +author, +thread, +parent, paras, +ptr}:
      match paras:
        case Nil{}:
          (Unit{}, (hr, Unit{}))
        case Con{pa, +rest}:
          match pa:
            case P.Para{+pn, +pstart, +pend, +text}:
              cut_src(rest, src, cap, R.Record{id, ts, source, author, thread, parent,
                P.Para{pn, pstart, pend, text} <> rest, ptr},
                String.length(R.Record.header(R.Record{id, ts, source, author,
                  thread, parent, P.Para{pn, pstart, pend, text} <> rest, ptr})),
                0n, 0n, String.length(text), hr)

# a record of source src whole or cut on an empty shard: srcg
def lay_src(
  small: Bool,
  +src: String,
  +cap: Nat,
  +rec: R.Record,
  hr: srcr(src, rec)
) -> M1.StepAll(g => srcg(src, g), S.Shard.lay.if(small, cap, rec, R.Record.size(rec))):
  match small:
    case True{}:
      (Unit{}, (hr, Unit{}))
    case False{}:
      split_src(rec, src, cap, hr)

# a step of a record of source src from a srcg open shard: srcg
def step_src.if(
  fits: Bool,
  +src: String,
  +cap: Nat,
  +cur: List<&2, S.Item>,
  +size: Nat,
  +rec: R.Record,
  hcur: M1.All(S.Item, it => srcit(src, it), cur),
  +hr: {Laws.of_src(src, rec) == True{} : Bool}
) -> M1.StepAll(g => srcg(src, g),
  S.Shard.step.if(fits, cap, cur, size, rec, R.Record.size(rec))):
  match fits:
    case True{}:
      (Unit{}, M1.all_app(S.Item, it => srcit(src, it), cur, [S.Shard.whole(rec)], hcur,
        (hr, Unit{})))
    case False{}:
      M1.after_all(g => srcg(src, g), S.Shard.shut(cur, size),
        S.Shard.lay.if(Nat.is_le(R.Record.size(rec), cap), cap, rec, R.Record.size(rec)),
        M1.shut_all(g => srcg(src, g), cur, size, hcur),
        lay_src(Nat.is_le(R.Record.size(rec), cap), src, cap, rec, hr))

# a step of a record of source src from a srcg open shard: srcg
def step_src(
  +src: String,
  +cap: Nat,
  st: S.Open,
  +rec: R.Record,
  hst: srcg(src, st),
  hr: srcr(src, rec)
) -> M1.StepAll(g => srcg(src, g), S.Shard.step(cap, st, rec)):
  match st:
    case S.Open{+cur, +size}:
      step_src.if(Nat.is_le(Nat.add(size, R.Record.size(rec)), cap), src, cap, cur, size,
        rec, hst, hr)

# every shard packed from records of source src is srcg
def run_src(
  xs: List<&2, R.Record>,
  +src: String,
  +cap: Nat,
  +st: S.Open,
  hst: srcg(src, st),
  hxs: M1.All(R.Record, r => srcr(src, r), xs)
) -> M1.All(S.Open, g => srcg(src, g), S.Shard.run(xs, cap, st)):
  match xs:
    case Nil{}:
      (hst, Unit{})
    case Con{+rec, +rest}:
      match hxs:
        case (hr, hrest):
          M1.then_all(g => srcg(src, g), S.Shard.step(cap, st, rec), rest, cap,
            step_src(src, cap, st, rec, hst, hr),
            o => ho => run_src(rest, src, cap, o, ho, hrest))

# the record kept or not by Shard.only, all of source src
def src_only.at(
  b: Bool,
  +src: String,
  rec: R.Record,
  -rest: List<&2, R.Record>,
  eb: {Laws.of_src(src, rec) == b : Bool},
  ih: M1.All(R.Record, r => srcr(src, r), rest)
) -> M1.All(R.Record, r => srcr(src, r), S.Shard.only.if(b, rec, rest)):
  match b:
    case True{}:
      (eb, ih)
    case False{}:
      ih

# every record Shard.only(src, xs) keeps is of source src
def src_only(+src: String, xs: List<&2, R.Record>) -> M1.All(R.Record, r => srcr(src, r), S.Shard.only(src, xs)):
  match xs:
    case Nil{}:
      Unit{}
    case Con{rec, +rest}:
      match rec:
        case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
          src_only.at(String.eq(source, src), src,
            R.Record{id, ts, source, author, thread, parent, paras, ptr},
            S.Shard.only(src, rest), {==}, src_only(src, rest))

# laws/ShardHoldsOneSource.bend of an item of a made shard
def src_made(
  +src: String,
  -k: U32,
  g: S.Open,
  -f: Bool,
  -it: S.Item,
  hi: D1.Elem(S.Item, it, D2.shard.items(S.Shard.make(k, g, f))),
  okgg: srcg(src, g)
) -> srcit(src, it):
  match g:
    case S.Open{items, _size}:
      M1.all_elem(S.Item, i => srcit(src, i), items, it, okgg, hi)

# laws/ShardHoldsOneSource.bend of an item of a shard made of one of gs
def src_in(
  gs: List<&2, S.Open>,
  +src: String,
  -s: S.Shard,
  -it: S.Item,
  hi: D1.Elem(S.Item, it, D2.shard.items(s)),
  oks: M1.All(S.Open, g => srcg(src, g), gs),
  m: M1.made_in(gs, s)
) -> srcit(src, it):
  match m:
    case (g, (k, (f, (el, e)))):
      src_made(src, k, g, f, it,
        (%e : D1.Elem(S.Item, it, D2.shard.items(_)); hi),
        M1.all_elem(S.Open, g2 => srcg(src, g2), gs, g, oks, el))

# laws/ShardHoldsOneSource.bend: every item of a shard packed from Shard.only(src, xs) is of
# source src
def Laws.one_source(cap, n, src, xs, s, hs, it, hi):
  +c = U32.to_nat(cap)
  +ys = S.Shard.only(src, xs)
  +gs = S.Shard.run(ys, c, S.Open{[], 0n})
  src_in(gs, src, s, it, hi, run_src(ys, src, c, S.Open{[], 0n}, Unit{}, src_only(src, xs)),
    M1.number_elem(gs, n, s, hs))

# what only_from says of a record of the rest, said of rec ahead of it
def src_from.inr(
  -src: String,
  -rec: R.Record,
  -rest: List<&2, R.Record>,
  -r: R.Record,
  got: Pair(D1.Elem(R.Record, r, rest), {Laws.of_src(src, r) == True{} : Bool})
) -> Pair(D1.Elem(R.Record, r, rec <> rest), {Laws.of_src(src, r) == True{} : Bool}):
  match got:
    case (el, ok):
      (Inr{el}, ok)

# what only_from says of a record of xs
def src_from.ok(+src: String, xs: List<&2, R.Record>, +r: R.Record) -> Type:
  Pair(D1.Elem(R.Record, r, xs), {Laws.of_src(src, r) == True{} : Bool})

# what only_from says of the record kept or not
def src_from.at(
  b: Bool,
  +src: String,
  +rec: R.Record,
  -rest: List<&2, R.Record>,
  -r: R.Record,
  eb: {Laws.of_src(src, rec) == b : Bool},
  h: D1.Elem(R.Record, r, S.Shard.only.if(b, rec, S.Shard.only(src, rest))),
  ih: D1.Elem(R.Record, r, S.Shard.only(src, rest)) -> src_from.ok(src, rest, r)
) -> Pair(D1.Elem(R.Record, r, rec <> rest), {Laws.of_src(src, r) == True{} : Bool}):
  match b:
    case True{}:
      match h:
        case Inl{+e}:
          (Inl{e}, (%Equal.sym(R.Record, r, rec, e) : {Laws.of_src(src, _) == True{} : Bool}; eb))
        case Inr{h2}:
          src_from.inr(src, rec, rest, r, ih(h2))
    case False{}:
      src_from.inr(src, rec, rest, r, ih(h))

# every record Shard.only(src, xs) keeps is one of xs, of source src
def src_from(
  +src: String,
  xs: List<&2, R.Record>,
  -r: R.Record,
  h: D1.Elem(R.Record, r, S.Shard.only(src, xs))
) -> Pair(D1.Elem(R.Record, r, xs), {Laws.of_src(src, r) == True{} : Bool}):
  match xs:
    case Nil{}:
      Empty.absurd(Pair(D1.Elem(R.Record, r, []), {Laws.of_src(src, r) == True{} : Bool}), h)
    case Con{rec, +rest}:
      match rec:
        case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
          src_from.at(String.eq(source, src), src,
            R.Record{id, ts, source, author, thread, parent, paras, ptr}, rest, r, {==}, h,
            h2 => src_from(src, rest, r, h2))

def Laws.only_from(src, xs, r, h):
  src_from(src, xs, r, h)

# what only_all says of the record kept or not
def src_keeps.at(
  b: Bool,
  +src: String,
  +rec: R.Record,
  -rest: List<&2, R.Record>,
  -r: R.Record,
  eb: {Laws.of_src(src, rec) == b : Bool},
  h: D1.Elem(R.Record, r, rec <> rest),
  e: {Laws.of_src(src, r) == True{} : Bool},
  ih: D1.Elem(R.Record, r, rest) -> D1.Elem(R.Record, r, S.Shard.only(src, rest))
) -> D1.Elem(R.Record, r, S.Shard.only.if(b, rec, S.Shard.only(src, rest))):
  match b:
    case True{}:
      match h:
        case Inl{er}:
          Inl{er}
        case Inr{h2}:
          Inr{ih(h2)}
    case False{}:
      match h:
        case Inl{er}:
          Empty.absurd(D1.Elem(R.Record, r, S.Shard.only(src, rest)),
            M2.clash(Equal.trans(Bool, False{}, Laws.of_src(src, rec), True{},
              Equal.sym(Bool, Laws.of_src(src, rec), False{}, eb),
              (%er : {Laws.of_src(src, _) == True{} : Bool}; e))))
        case Inr{h2}:
          ih(h2)

# Shard.only(src, xs) keeps every record of xs of source src
def src_keeps(
  +src: String,
  xs: List<&2, R.Record>,
  -r: R.Record,
  h: D1.Elem(R.Record, r, xs),
  +e: {Laws.of_src(src, r) == True{} : Bool}
) -> D1.Elem(R.Record, r, S.Shard.only(src, xs)):
  match xs:
    case Nil{}:
      Empty.absurd(D1.Elem(R.Record, r, []), h)
    case Con{rec, +rest}:
      match rec:
        case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
          src_keeps.at(String.eq(source, src), src,
            R.Record{id, ts, source, author, thread, parent, paras, ptr}, rest, r, {==}, h, e,
            h2 => src_keeps(src, rest, r, h2, e))

def Laws.only_all(src, xs, r, h, e):
  src_keeps(src, xs, r, h, e)
