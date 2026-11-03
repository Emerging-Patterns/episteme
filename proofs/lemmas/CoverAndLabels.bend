# a tile covers every code point that is not whitespace, and a shard's labels
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../src/excerpt.bend as E
import ../../src/git.bend as G
import ../../laws/ShardLabelsNumberParagraphs.bend as L1
import ../../laws/defs/Specification.bend as D1
import ./BoolFacts.bend as M1
import ./NatArithmetic.bend as M2
import ./OffsetsHeld.bend as M3

# i below s, or s at most i
def tri(i: Nat, s: Nat) -> Type:
  Or(Exists(Nat, b => {Nat.add(i, 1n+b) == s : Nat}),
    Exists(Nat, a => {Nat.add(s, a) == i : Nat}))

# tri one up
def tri.up(-p: Nat, -q: Nat, r: tri(p, q)) -> tri(1n+p, 1n+q):
  match r:
    case Inl{x}:
      match x:
        case (b, e):
          Inl{(b, Equal.cong(Nat, Nat, z => 1n+z, Nat.add(p, 1n+b), q, e))}
    case Inr{x}:
      match x:
        case (a, e):
          Inr{(a, Equal.cong(Nat, Nat, z => 1n+z, Nat.add(q, a), p, e))}

# tri holds of every two numbers
def split2(+i: Nat, +s: Nat) -> tri(i, s):
  match i s:
    case _ 0n:
      Inr{(i, {==})}
    case 0n 1n+q:
      Inl{(q, {==})}
    case 1n+p 1n+q:
      tri.up(p, q, split2(p, q))

# an empty gap from E to S leaves nothing below S past E
def gap_char.nil(
  +E: Nat,
  +a: Nat,
  -i: Nat,
  +b: Nat,
  -S: Nat,
  el: {Nat.add(E, 0n) == S : Nat},
  ei: {Nat.add(E, a) == i : Nat},
  lt: {Nat.add(i, 1n+b) == S : Nat}
) -> Empty:
  M2.no_loop(E, Nat.add(a, b),
    Equal.trans(Nat, Nat.add(E, 1n+Nat.add(a, b)), Nat.add(E, Nat.add(a, 1n+b)), E,
      Equal.cong(Nat, Nat, z => Nat.add(E, z), 1n+Nat.add(a, b), Nat.add(a, 1n+b),
        Equal.sym(Nat, Nat.add(a, 1n+b), 1n+Nat.add(a, b), M2.add_succ_r(a, b))),
      Equal.trans(Nat, Nat.add(E, Nat.add(a, 1n+b)), Nat.add(Nat.add(E, a), 1n+b), E,
        Equal.sym(Nat, Nat.add(Nat.add(E, a), 1n+b), Nat.add(E, Nat.add(a, 1n+b)),
          M2.add_assoc(E, a, 1n+b)),
        Equal.trans(Nat, Nat.add(Nat.add(E, a), 1n+b), S, E,
          (%Equal.sym(Nat, Nat.add(E, a), i, ei)
            : {Nat.add(_, 1n+b) == S : Nat}; lt),
          Equal.trans(Nat, S, Nat.add(E, 0n), E,
            Equal.sym(Nat, Nat.add(E, 0n), S, el), M2.add_zero_r(E))))))

# the code point at E + a, below S, inside a gap from E to S is whitespace
def gap_char(
  +a: Nat,
  +T: String,
  +E: Nat,
  -S: Nat,
  -i: Nat,
  -c: Char,
  -u: String,
  +b: Nat,
  g: M1.gap(T, E, S),
  ei: {Nat.add(E, a) == i : Nat},
  ed: {String.drop(T, i) == SCon{c, u} : String},
  lt: {Nat.add(i, 1n+b) == S : Nat}
) -> {Char.is_space(c) == True{} : Bool}:
  match a:
    case 0n:
      match g:
        case (G, r):
          match G:
            case SNil{}:
              match r:
                case (_eg, (el, _ebl)):
                  Empty.absurd({Char.is_space(c) == True{} : Bool},
                    gap_char.nil(E, 0n, i, b, S, el, ei, lt))
            case SCon{+g0, +G2}:
              match r:
                case (eg, (_el, ebl)):
                  %Equal.cong(String, Char,
                      z => M1.hd(z, g0), SCon{g0, G2 ++ String.drop(T, S)},
                      SCon{c, u},
                      Equal.trans(String, SCon{g0, G2 ++ String.drop(T, S)},
                        String.drop(T, E), SCon{c, u},
                        Equal.sym(String, String.drop(T, E),
                          SCon{g0, G2 ++ String.drop(T, S)}, eg),
                        (%Equal.sym(Nat, E, i, Equal.trans(Nat, E,
                            Nat.add(E, 0n), i,
                            Equal.sym(Nat, Nat.add(E, 0n), E, M2.add_zero_r(E)),
                            ei))
                          : {String.drop(T, _) == SCon{c, u} : String}; ed)))
                    : {Char.is_space(_) == True{} : Bool}
                  M1.and_l(Char.is_space(g0), D1.blank(G2), ebl)
    case 1n+p:
      match g:
        case (G, r):
          match G:
            case SNil{}:
              match r:
                case (_eg, (el, _ebl)):
                  Empty.absurd({Char.is_space(c) == True{} : Bool},
                    gap_char.nil(E, 1n+p, i, b, S, el, ei, lt))
            case SCon{+g0, +G2}:
              match r:
                case (eg, (el, ebl)):
                  gap_char(p, T, 1n+E, S, i, c, u, b,
                    (G2, (M2.drop_step(T, E, g0, G2 ++ String.drop(T, S), eg),
                      (Equal.trans(Nat, 1n+Nat.add(E, String.length(G2)),
                        Nat.add(E, 1n+String.length(G2)), S,
                        Equal.sym(Nat, Nat.add(E, 1n+String.length(G2)),
                          1n+Nat.add(E, String.length(G2)),
                          M2.add_succ_r(E, String.length(G2))), el),
                      M1.and_r(Char.is_space(g0), D1.blank(G2), ebl)))),
                    Equal.trans(Nat, 1n+Nat.add(E, p), Nat.add(E, 1n+p), i,
                      Equal.sym(Nat, Nat.add(E, 1n+p), 1n+Nat.add(E, p),
                        M2.add_succ_r(E, p)), ei),
                    ed, lt)

# --- a tile covers every code point that is not whitespace ---

# a paragraph ahead of ps keeps ps's hit
def hits_cons(
  -T: String,
  -i: Nat,
  -x: P.Para,
  -ps: List<&2, P.Para>,
  h: M3.hits(T, i, ps)
) -> M3.hits(T, i, Con{x, ps}):
  match h:
    case (p, (inp, ht)):
      (p, (Inr{inp}, ht))

# the end of a tile: the rest of T is whitespace, so i is no code point of
# it that is not
def cover.nil(
  +T: String,
  +E: Nat,
  +a: Nat,
  -i: Nat,
  -c: Char,
  -u: String,
  t: M1.gap(T, E, String.length(T)),
  ei: {Nat.add(E, a) == i : Nat},
  ed: {String.drop(T, i) == SCon{c, u} : String},
  es: {Char.is_space(c) == False{} : Bool},
  x: Exists(Nat, b => {Nat.add(i, 1n+b) == String.length(T) : Nat})
) -> M3.hits(T, i, Nil{}):
  match x:
    case (b, lt):
      Empty.absurd(M3.hits(T, i, Nil{}), M1.clash(Equal.trans(Bool, False{},
        Char.is_space(c), True{}, Equal.sym(Bool, Char.is_space(c), False{}, es),
        gap_char(a, T, E, String.length(T), i, c, u, b, t, ei, ed, lt))))

# the first paragraph of a tile: i is before it (whitespace), in it, or
# after it
def cover.k(
  +T: String,
  +E: Nat,
  +a: Nat,
  +i: Nat,
  -c: Char,
  -u: String,
  +n: U32,
  +s: U32,
  +e: U32,
  +x: String,
  -rest: List<&2, P.Para>,
  +ks: Nat,
  +ke: Nat,
  es1: {s == U32.from_nat(ks) : U32},
  ee: {e == U32.from_nat(ke) : U32},
  g: M1.gap(T, E, ks),
  qq: Exists(Nat, q => {Nat.add(ke, q) == String.length(T) : Nat}),
  ei: {Nat.add(E, a) == i : Nat},
  ed: {String.drop(T, i) == SCon{c, u} : String},
  es: {Char.is_space(c) == False{} : Bool},
  r: tri(i, ks),
  r2: tri(i, ke),
  ih: @a3: Nat -> {Nat.add(ke, a3) == i : Nat} -> M3.hits(T, i, rest)
) -> M3.hits(T, i, Con{P.Para{n, s, e, x}, rest}):
  match r:
    case Inl{y}:
      match y:
        case (b, lt):
          Empty.absurd(M3.hits(T, i, Con{P.Para{n, s, e, x}, rest}),
            M1.clash(Equal.trans(Bool, False{}, Char.is_space(c), True{},
              Equal.sym(Bool, Char.is_space(c), False{}, es),
              gap_char(a, T, E, ks, i, c, u, b, g, ei, ed, lt))))
    case Inr{y}:
      match r2:
        case Inl{z}:
          (P.Para{n, s, e, x}, (Inl{{==}}, (ks, (ke, (es1, (ee, (y, (z, qq))))))))
        case Inr{z}:
          match z:
            case (a3, e3):
              hits_cons(T, i, P.Para{n, s, e, x}, rest, ih(a3, e3))

# every code point of T from E on that is not whitespace lies in a
# paragraph of a tile from E to the end
def cover(
  ps: List<&2, P.Para>,
  +T: String,
  +E: Nat,
  +a: Nat,
  +i: Nat,
  +c: Char,
  +u: String,
  t: M2.tile(T, E, ps, String.length(T)),
  ei: {Nat.add(E, a) == i : Nat},
  +ed: {String.drop(T, i) == SCon{c, u} : String},
  +es: {Char.is_space(c) == False{} : Bool}
) -> M3.hits(T, i, ps):
  match ps:
    case Nil{}:
      cover.nil(T, E, a, i, c, u, t, ei, ed, es, M2.drop_len(T, i, c, u, ed))
    case Con{p, rest}:
      match p:
        case P.Para{n, s, e, x}:
          match t:
            case (+ks, (+ke, (es1, (ee, (g, (_d, (qq, t3))))))):
              cover.k(T, E, a, i, c, u, n, s, e, x, rest, ks, ke, es1, ee, g, qq,
                ei, ed, es, split2(i, ks), split2(i, ke),
                a3 => e3 => cover(rest, T, ke, a3, i, c, u, t3, e3, ed, es))

# --- labels ---

# the shard's pairs are the specification's
law pairs_same:
  for +rec: R.Record
  for ps: List<&2, P.Para>
  {S.Shard.pairs(rec, ps) == D1.pairs(rec, ps) : List<&2, S.Shard.Line()>}

def pairs_same(rec, ps):
  match ps:
    case Nil{}:
      {==}
    case Con{+pa, rest}:
      Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
        x => (rec, pa) <> x, S.Shard.pairs(rec, rest), D1.pairs(rec, rest),
        pairs_same(rec, rest))

# the shard's lines are the specification's cover
law lines_same:
  for its: List<&2, S.Item>
  {S.Shard.lines(its) == D1.items.cover(its) : List<&2, S.Shard.Line()>}

def lines_same(its):
  match its:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case S.Item{rec, +from, +upto}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
              %Equal.sym(List<&2, S.Shard.Line()>,
                S.Shard.pairs(R.Record{id, ts, source, author, thread, parent,
                  paras, ptr}, S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                  author, thread, parent, paras, ptr}, from, upto})),
                D1.pairs(R.Record{id, ts, source, author, thread, parent,
                  paras, ptr}, S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                  author, thread, parent, paras, ptr}, from, upto})),
                pairs_same(R.Record{id, ts, source, author, thread, parent,
                  paras, ptr}, S.Shard.item.paras(S.Item{R.Record{id, ts, source,
                  author, thread, parent, paras, ptr}, from, upto})))
                : {List.append(&2, S.Shard.Line(), _, S.Shard.lines(rest))
                  == D1.items.cover(Con{S.Item{R.Record{id, ts, source, author,
                    thread, parent, paras, ptr}, from, upto}, rest})
                  : List<&2, S.Shard.Line()>}
              Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
                x => List.append(&2, S.Shard.Line(), D1.pairs(R.Record{id, ts,
                  source, author, thread, parent, paras, ptr},
                  S.Shard.item.paras(S.Item{R.Record{id, ts, source, author,
                  thread, parent, paras, ptr}, from, upto})), x),
                S.Shard.lines(rest), D1.items.cover(rest), lines_same(rest))

# the shard's labels are the specification's tags
law labels_same:
  for ps: List<&2, S.Shard.Line()>
  for +k: U32
  {S.Shard.labels.go(ps, k) == L1.tags(ps, k) : List<&2, S.Shard.Label()>}

def labels_same(ps, k):
  match ps:
    case Nil{}:
      {==}
    case Con{line, rest}:
      match line:
        case (rec, pa):
          match rec pa:
            case R.Record{+id, _ts, _source, _author, _thread, _parent, _paras, _ptr}
              P.Para{+n, _start, _end, _text}:
              Equal.cong(List<&2, S.Shard.Label()>, List<&2, S.Shard.Label()>,
                x => (S.Shard.label(k), (id, n)) <> x,
                S.Shard.labels.go(rest, U32.inc(k)), L1.tags(rest, U32.inc(k)),
                labels_same(rest, U32.inc(k)))

# a shard's labels are p1, p2, ... over its paragraphs in order
def L1.labels_cover(s):
  match s:
    case S.Shard{_n, +items, _sources, _chars, _frozen}:
      %Equal.sym(List<&2, S.Shard.Line()>, S.Shard.lines(items),
        D1.items.cover(items), lines_same(items))
        : {S.Shard.labels.go(_, 1) == L1.tags(D1.items.cover(items), 1)
          : List<&2, S.Shard.Label()>}
      labels_same(D1.items.cover(items), 1)
