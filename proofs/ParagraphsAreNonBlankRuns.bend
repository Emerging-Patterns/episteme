# proofs of laws/ParagraphsAreNonBlankRuns.bend
import Base
import ../src/para.bend as P
import ../src/git.bend as G
import ../laws/ParagraphsAreNonBlankRuns.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/CoverAndLabels.bend as M2
import ./lemmas/NatArithmetic.bend as M3
import ./lemmas/OffsetsHeld.bend as M4
import ./lemmas/PackingSteps.bend as M5
import ./lemmas/ParagraphScan.bend as M6
import ./lemmas/TakeAndAppend.bend as M7

# --- where a code point is ---

# the value of a Some, or d
def mval(m: Maybe<&2, Char>, d: Char) -> Char:
  match m:
    case None{}:
      d
    case Some{v}:
      v

# Unit for None, Empty for Some
def isnone(m: Maybe<&2, Char>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{_v}:
      Empty

# the code point at i is the head of what dropping i leaves
def get_drop(
  x: String,
  +i: Nat,
  -c: Char,
  e: {String.get(x, i) == Some{c} : Maybe<&2, Char>}
) -> Exists(String, u => {String.drop(x, i) == SCon{c, u} : String}):
  match x i:
    case SNil{} _:
      Empty.absurd(Exists(String, u => {String.drop(SNil{}, i) == SCon{c, u} : String}),
        (%e : isnone(_); Unit{}))
    case SCon{+h, +t} 0n:
      (t, Equal.cong(Char, String, z => SCon{z, t}, h, c,
        Equal.cong(Maybe<&2, Char>, Char, m => mval(m, h), Some{h}, Some{c}, e)))
    case SCon{_h, t} 1n+p:
      get_drop(t, p, c, e)

# the tile half
def split_tile(
  -T: String,
  r: M6.splitres(T)
) -> M3.tile(T, 0n, P.Para.split(T), String.length(T)):
  match r:
    case (_a, t):
      t

# a good paragraph is not blank
def nonblank_of_good(
  -T: String,
  -cap: Nat,
  p: P.Para,
  g: M5.good(T, cap, p)
) -> {D1.blank(D1.para.text(p)) == False{} : Bool}:
  match p:
    case P.Para{_n, _s, _e, t}:
      match g:
        case (_o, (_le, (nb, _nob))):
          Equal.trans(Bool, D1.blank(t), P.Para.blank(t), False{},
            Equal.sym(Bool, P.Para.blank(t), D1.blank(t), M7.blank_same(t)), nb)

# a paragraph from ks to ke holding offset i, read at its U32 offsets
def hit_fin2(
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  +i: Nat,
  -s: U32,
  -e: U32,
  +ks: Nat,
  +ke: Nat,
  +a: Nat,
  +b: Nat,
  +q: Nat,
  es: {s == U32.from_nat(ks) : U32},
  ee: {e == U32.from_nat(ke) : U32},
  +ea: {Nat.add(ks, a) == i : Nat},
  +eb: {Nat.add(i, 1n+b) == ke : Nat},
  +eq: {Nat.add(ke, q) == String.length(T) : Nat}
) -> Pair({Nat.is_le(U32.to_nat(s), i) == True{} : Bool},
  {Nat.is_lt(i, U32.to_nat(e)) == True{} : Bool}):
  ((%Equal.sym(U32, s, U32.from_nat(ks), es)
      : {Nat.is_le(U32.to_nat(_), i) == True{} : Bool}
    %Equal.sym(Nat, U32.to_nat(U32.from_nat(ks)), ks,
        M3.rt_add(ks, Nat.add(a, 1n+b),
          M3.rt_cast(ke, Nat.add(ks, Nat.add(a, 1n+b)),
            Equal.sym(Nat, Nat.add(ks, Nat.add(a, 1n+b)), ke,
              Equal.trans(Nat, Nat.add(ks, Nat.add(a, 1n+b)),
                Nat.add(Nat.add(ks, a), 1n+b), ke,
                Equal.sym(Nat, Nat.add(Nat.add(ks, a), 1n+b),
                  Nat.add(ks, Nat.add(a, 1n+b)), M3.add_assoc(ks, a, 1n+b)),
                (%Equal.sym(Nat, Nat.add(ks, a), i, ea)
                  : {Nat.add(_, 1n+b) == ke : Nat}; eb))),
            M3.rt_add(ke, q, M3.rt_cast(String.length(T), Nat.add(ke, q),
              Equal.sym(Nat, Nat.add(ke, q), String.length(T), eq),
              fits)))))
      : {Nat.is_le(_, i) == True{} : Bool}
    %ea : {Nat.is_le(ks, _) == True{} : Bool}
    M3.le_add(ks, a)),
  (%Equal.sym(U32, e, U32.from_nat(ke), ee)
      : {Nat.is_lt(i, U32.to_nat(_)) == True{} : Bool}
    %Equal.sym(Nat, U32.to_nat(U32.from_nat(ke)), ke,
        M3.rt_add(ke, q, M3.rt_cast(String.length(T), Nat.add(ke, q),
          Equal.sym(Nat, Nat.add(ke, q), String.length(T), eq), fits)))
      : {Nat.is_lt(i, _) == True{} : Bool}
    %eb : {Nat.is_lt(i, _) == True{} : Bool}
    M6.lt_add(i, b)))

# a paragraph that holds offset i, read at its U32 offsets
def hit_fin(
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  +i: Nat,
  p: P.Para,
  ht: M4.hitn(T, i, p)
) -> Pair({Nat.is_le(U32.to_nat(D1.para.start(p)), i) == True{} : Bool},
  {Nat.is_lt(i, U32.to_nat(D1.para.end(p))) == True{} : Bool}):
  match p:
    case P.Para{_n, s, e, _x}:
      match ht:
        case (ks, (ke, (es, (ee, ((a, ea), ((b, eb), (q, eq))))))):
          hit_fin2(T, fits, i, s, e, ks, ke, a, b, q, es, ee, ea, eb, eq)

# the paragraph that holds i, read at its U32 offsets
def cover_fin(
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  +i: Nat,
  h: M4.hits(T, i, P.Para.split(T))
) -> Exists(P.Para, p => Pair(D1.In(p, P.Para.split(T)),
  Pair({Nat.is_le(U32.to_nat(D1.para.start(p)), i) == True{} : Bool},
    {Nat.is_lt(i, U32.to_nat(D1.para.end(p))) == True{} : Bool}))):
  match h:
    case (+p, (inp, ht)):
      (p, (inp, hit_fin(T, fits, i, p, ht)))

# the code point at i, not whitespace, lies in some paragraph
def cover_law(
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  +i: Nat,
  +c: Char,
  +hs: {Char.is_space(c) == False{} : Bool},
  x: Exists(String, u => {String.drop(T, i) == SCon{c, u} : String})
) -> Exists(P.Para, p => Pair(D1.In(p, P.Para.split(T)),
  Pair({Nat.is_le(U32.to_nat(D1.para.start(p)), i) == True{} : Bool},
    {Nat.is_lt(i, U32.to_nat(D1.para.end(p))) == True{} : Bool}))):
  match x:
    case (u, ed):
      cover_fin(T, fits, i, M2.cover(P.Para.split(T), T, 0n, i, i, c, u,
        split_tile(T, M6.split_ok(T)), {==}, ed, hs))

# --- paragraphs tile the text in order ---

# dropping all of s leaves nothing
def drop_end(s: String) -> {String.drop(s, String.length(s)) == SNil{} : String}:
  match s:
    case SNil{}:
      {==}
    case SCon{_h, t}:
      drop_end(t)

# a prefix of a blank string is blank
def blank_take(
  s: String,
  n: Nat,
  +e: {D1.blank(s) == True{} : Bool}
) -> {D1.blank(String.take(s, n)) == True{} : Bool}:
  match s:
    case SNil{}:
      {==}
    case SCon{+h, t}:
      match n:
        case 0n:
          {==}
        case 1n+m:
          %Equal.sym(Bool, Char.is_space(h), True{}, M1.and_l(Char.is_space(h), D1.blank(t), e))
            : {Bool.and(_, D1.blank(String.take(t, m))) == True{} : Bool}
          blank_take(t, m, M1.and_r(Char.is_space(h), D1.blank(t), e))

# a string with a prefix that is not blank is not blank
def not_blank(
  b: Bool,
  +s: String,
  +n: Nat,
  eb: {D1.blank(s) == b : Bool},
  et: {D1.blank(String.take(s, n)) == False{} : Bool}
) -> {D1.blank(s) == False{} : Bool}:
  match b:
    case True{}:
      Empty.absurd({D1.blank(s) == False{} : Bool},
        M1.clash(Equal.trans(Bool, False{}, D1.blank(String.take(s, n)), True{},
          Equal.sym(Bool, D1.blank(String.take(s, n)), False{}, et),
          blank_take(s, n, eb))))
    case False{}:
      eb

# whitespace from lo to the end of T: T from lo on is blank
def gap_end(
  +T: String,
  +lo: Nat,
  g: M1.gap(T, lo, String.length(T))
) -> {D1.blank(String.drop(T, lo)) == True{} : Bool}:
  match g:
    case (+G, (eG, (_el, ebG))):
      %Equal.sym(String, String.drop(T, lo), G ++ String.drop(T, String.length(T)), eG)
        : {D1.blank(_) == True{} : Bool}
      %Equal.sym(String, String.drop(T, String.length(T)), SNil{}, drop_end(T))
        : {D1.blank(G ++ _) == True{} : Bool}
      %Equal.sym(String, G ++ "", G, M6.app_nil(G)) : {D1.blank(_) == True{} : Bool}
      ebG

# T from lo on is not blank when a paragraph follows
def nxt(T: String, lo: Nat, ps: List<&2, P.Para>) -> Type:
  match ps:
    case Nil{}:
      Unit
    case Con{_p, _r}:
      {D1.blank(String.drop(T, lo)) == False{} : Bool}

# what tiled reads of a paragraph p: its slice, not blank, no blank line,
# and where it ends
def pfacts(T: String, p: P.Para) -> Type:
  Pair({D1.slice(T, U32.to_nat(D1.para.start(p)), U32.to_nat(D1.para.end(p)))
    == D1.para.text(p) : String},
  Pair({D1.blank(D1.para.text(p)) == False{} : Bool},
  Pair({Laws.lines_full(D1.para.text(p)) == True{} : Bool},
    M5.endr(T, U32.to_nat(P.Para.max()), U32.to_nat(D1.para.end(p)), D1.para.text(p)))))

# a good paragraph's facts, from its parts
def pfacts2(
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  -n: U32,
  -s: U32,
  -e: U32,
  +t: String,
  +k: Nat,
  +l: Nat,
  +q: Nat,
  es: {s == U32.from_nat(k) : U32},
  +ee: {e == U32.from_nat(Nat.add(l, k)) : U32},
  et: {String.take(String.drop(T, k), l) == t : String},
  +eq: {Nat.add(Nat.add(l, k), q) == String.length(T) : Nat},
  ec: M5.endr(T, U32.to_nat(P.Para.max()), Nat.add(l, k), t),
  nb: {P.Para.blank(t) == False{} : Bool},
  nob: {Laws.lines_full(t) == True{} : Bool}
) -> pfacts(T, P.Para{n, s, e, t}):
  (M6.offsets_fin(T, l, k, s, e, t, es, ee, et, M6.rt_end(T, l, k, q, eq, fits)),
    (Equal.trans(Bool, D1.blank(t), P.Para.blank(t), False{},
      Equal.sym(Bool, P.Para.blank(t), D1.blank(t), M7.blank_same(t)), nb),
    (nob,
      (%Equal.sym(Nat, U32.to_nat(e), Nat.add(l, k),
          Equal.trans(Nat, U32.to_nat(e), U32.to_nat(U32.from_nat(Nat.add(l, k))),
            Nat.add(l, k),
            Equal.cong(U32, Nat, z => U32.to_nat(z), e, U32.from_nat(Nat.add(l, k)), ee),
            M6.rt_end(T, l, k, q, eq, fits)))
        : M5.endr(T, U32.to_nat(P.Para.max()), _, t);
        ec))))

# a good paragraph's facts
def pfacts_of(
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  p: P.Para,
  g: M5.good(T, U32.to_nat(P.Para.max()), p)
) -> pfacts(T, p):
  match p:
    case P.Para{n, s, e, t}:
      match g:
        case (o, w):
          match o:
            case (k, (l, (es, (ee, (et, (qe, ec)))))):
              match qe:
                case (q, eq):
                  match w:
                    case (_le, (nb, nob)):
                      pfacts2(T, fits, n, s, e, t, k, l, q, es, ee, et, eq, ec, nb, nob)

# between p and the paragraphs after it: a blank line, unless p was cut
def sep_of(
  rest: List<&2, P.Para>,
  -T: String,
  -n: U32,
  -s: U32,
  -e: U32,
  -t: String,
  -ke: Nat,
  ete: {U32.to_nat(e) == ke : Nat},
  h: nxt(T, ke, rest),
  f: M5.endr(T, U32.to_nat(P.Para.max()), U32.to_nat(e), t)
) -> Laws.sep(T, P.Para{n, s, e, t}, rest):
  match rest:
    case Nil{}:
      Unit{}
    case Con{x, y}:
      match f:
        case Inl{z}:
          match z:
            case Inl{w}:
              match w:
                case (eb, _r):
                  Empty.absurd(Laws.sep(T, P.Para{n, s, e, t}, Con{x, y}),
                    M1.clash(Equal.trans(Bool, False{}, D1.blank(String.drop(T, ke)), True{},
                      Equal.sym(Bool, D1.blank(String.drop(T, ke)), False{}, h),
                      (%ete : {D1.blank(String.drop(T, _)) == True{} : Bool}; eb))))
            case Inr{fb}:
              Inl{fb}
        case Inr{c}:
          Inr{c}

# p from ks to ke tiled after lo, past the whitespace G: what tiled says of
# it and the rest
def tiled_fin3(
  rest: List<&2, P.Para>,
  +T: String,
  -n: U32,
  +s: U32,
  +e: U32,
  -t: String,
  +lo: Nat,
  +ks: Nat,
  +ke: Nat,
  +d: Nat,
  +ets: {U32.to_nat(s) == ks : Nat},
  +ete: {U32.to_nat(e) == ke : Nat},
  +G: String,
  +eG: {String.drop(T, lo) == G ++ String.drop(T, ks) : String},
  +elG: {Nat.add(lo, String.length(G)) == ks : Nat},
  +ebG: {D1.blank(G) == True{} : Bool},
  ed: {Nat.add(ks, d) == ke : Nat},
  pf: pfacts(T, P.Para{n, s, e, t}),
  r: Pair(Laws.tiled(T, ke, rest), nxt(T, ke, rest))
) -> Pair(Laws.tiled(T, lo, Con{P.Para{n, s, e, t}, rest}),
  {D1.blank(String.drop(T, lo)) == False{} : Bool}):
  match pf:
    case (eo, (enb, (nob, f))):
      match r:
        case (tr, h):
          ((%Equal.sym(Nat, U32.to_nat(s), ks, ets) : {Nat.is_le(lo, _) == True{} : Bool}
            %elG : {Nat.is_le(lo, _) == True{} : Bool}
            M3.le_add(lo, String.length(G)),
          ((%Equal.sym(Nat, U32.to_nat(s), ks, ets)
              : {D1.blank(D1.slice(T, lo, _)) == True{} : Bool}
            %Equal.sym(String, String.drop(T, lo), G ++ String.drop(T, ks), eG)
              : {D1.blank(String.take(_, Nat.sub(ks, lo))) == True{} : Bool}
            %elG
              : {D1.blank(String.take(G ++ String.drop(T, ks), Nat.sub(_, lo)))
                == True{} : Bool}
            %M3.add_comm(String.length(G), lo)
              : {D1.blank(String.take(G ++ String.drop(T, ks), Nat.sub(_, lo)))
                == True{} : Bool}
            %Equal.sym(Nat, Nat.sub(Nat.add(String.length(G), lo), lo), String.length(G),
                M6.sub_add(String.length(G), lo))
              : {D1.blank(String.take(G ++ String.drop(T, ks), _)) == True{} : Bool}
            %Equal.sym(String, String.take(G ++ String.drop(T, ks), String.length(G)), G,
                M7.take_app(G, String.drop(T, ks)))
              : {D1.blank(_) == True{} : Bool}
            ebG),
          ((%Equal.sym(Nat, U32.to_nat(s), ks, ets)
              : {Nat.is_le(_, U32.to_nat(e)) == True{} : Bool}
            %Equal.sym(Nat, U32.to_nat(e), ke, ete) : {Nat.is_le(ks, _) == True{} : Bool}
            %ed : {Nat.is_le(ks, _) == True{} : Bool}
            M3.le_add(ks, d)),
          (nob,
          (sep_of(rest, T, n, s, e, t, ke, ete, h, f),
            (%Equal.sym(Nat, U32.to_nat(e), ke, ete) : Laws.tiled(T, _, rest); tr)))))),
          (%Equal.sym(String, String.drop(T, lo), G ++ String.drop(T, ks), eG)
              : {D1.blank(_) == False{} : Bool}
            %Equal.sym(Bool, D1.blank(G ++ String.drop(T, ks)),
                Bool.and(D1.blank(G), D1.blank(String.drop(T, ks))),
                M6.blank_app_eq(G, String.drop(T, ks)))
              : {_ == False{} : Bool}
            %Equal.sym(Bool, D1.blank(G), True{}, ebG)
              : {Bool.and(_, D1.blank(String.drop(T, ks))) == False{} : Bool}
            %ets : {D1.blank(String.drop(T, _)) == False{} : Bool}
            not_blank(D1.blank(String.drop(T, U32.to_nat(s))),
              String.drop(T, U32.to_nat(s)), Nat.sub(U32.to_nat(e), U32.to_nat(s)), {==},
              (%Equal.sym(String, D1.slice(T, U32.to_nat(s), U32.to_nat(e)), t, eo)
                : {D1.blank(_) == False{} : Bool}; enb))))

# p from ks to ke tiled after lo: what tiled says of it and the rest
def tiled_fin2(
  rest: List<&2, P.Para>,
  +T: String,
  -n: U32,
  +s: U32,
  +e: U32,
  -t: String,
  +lo: Nat,
  +ks: Nat,
  +ke: Nat,
  +d: Nat,
  +ets: {U32.to_nat(s) == ks : Nat},
  +ete: {U32.to_nat(e) == ke : Nat},
  gE: M1.gap(T, lo, ks),
  ed: {Nat.add(ks, d) == ke : Nat},
  pf: pfacts(T, P.Para{n, s, e, t}),
  r: Pair(Laws.tiled(T, ke, rest), nxt(T, ke, rest))
) -> Pair(Laws.tiled(T, lo, Con{P.Para{n, s, e, t}, rest}),
  {D1.blank(String.drop(T, lo)) == False{} : Bool}):
  match gE:
    case (G, (eG, (elG, ebG))):
      tiled_fin3(rest, T, n, s, e, t, lo, ks, ke, d, ets, ete, G, eG, elG, ebG, ed, pf, r)

# p from ks to ke tiled after lo, read at its U32 offsets
def tiled_fin(
  rest: List<&2, P.Para>,
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  -n: U32,
  +s: U32,
  +e: U32,
  -t: String,
  +lo: Nat,
  +ks: Nat,
  +ke: Nat,
  +d: Nat,
  +q: Nat,
  es: {s == U32.from_nat(ks) : U32},
  ee: {e == U32.from_nat(ke) : U32},
  gE: M1.gap(T, lo, ks),
  +ed: {Nat.add(ks, d) == ke : Nat},
  +eq: {Nat.add(ke, q) == String.length(T) : Nat},
  pf: pfacts(T, P.Para{n, s, e, t}),
  r: Pair(Laws.tiled(T, ke, rest), nxt(T, ke, rest))
) -> Pair(Laws.tiled(T, lo, Con{P.Para{n, s, e, t}, rest}),
  {D1.blank(String.drop(T, lo)) == False{} : Bool}):
  tiled_fin2(rest, T, n, s, e, t, lo, ks, ke, d,
    Equal.trans(Nat, U32.to_nat(s), U32.to_nat(U32.from_nat(ks)), ks,
      Equal.cong(U32, Nat, z => U32.to_nat(z), s, U32.from_nat(ks), es),
      M3.rt_add(ks, d, M3.rt_cast(ke, Nat.add(ks, d), Equal.sym(Nat, Nat.add(ks, d), ke, ed),
        M3.rt_add(ke, q, M3.rt_cast(String.length(T), Nat.add(ke, q),
          Equal.sym(Nat, Nat.add(ke, q), String.length(T), eq), fits))))),
    Equal.trans(Nat, U32.to_nat(e), U32.to_nat(U32.from_nat(ke)), ke,
      Equal.cong(U32, Nat, z => U32.to_nat(z), e, U32.from_nat(ke), ee),
      M3.rt_add(ke, q, M3.rt_cast(String.length(T), Nat.add(ke, q),
        Equal.sym(Nat, Nat.add(ke, q), String.length(T), eq), fits))),
    gE, ed, pf, r)

# p from ks to ke tiled after lo, with its length and what follows it
def tiled_fin0(
  rest: List<&2, P.Para>,
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  -n: U32,
  +s: U32,
  +e: U32,
  -t: String,
  +lo: Nat,
  +ks: Nat,
  +ke: Nat,
  es: {s == U32.from_nat(ks) : U32},
  ee: {e == U32.from_nat(ke) : U32},
  gE: M1.gap(T, lo, ks),
  dd: Exists(Nat, d => {Nat.add(ks, d) == ke : Nat}),
  qq: Exists(Nat, q => {Nat.add(ke, q) == String.length(T) : Nat}),
  pf: pfacts(T, P.Para{n, s, e, t}),
  r: Pair(Laws.tiled(T, ke, rest), nxt(T, ke, rest))
) -> Pair(Laws.tiled(T, lo, Con{P.Para{n, s, e, t}, rest}),
  {D1.blank(String.drop(T, lo)) == False{} : Bool}):
  match dd:
    case (d, ed):
      match qq:
        case (q, eq):
          tiled_fin(rest, T, fits, n, s, e, t, lo, ks, ke, d, q, es, ee, gE, ed, eq, pf, r)

# good paragraphs tiled from lo to the end of T are tiled as the law reads
# it, and T from lo on is not blank when one follows
def tiled_of(
  ps: List<&2, P.Para>,
  +T: String,
  +fits: {U32.to_nat(U32.from_nat(String.length(T))) == String.length(T) : Nat},
  +lo: Nat,
  tl: M3.tile(T, lo, ps, String.length(T)),
  a: M5.all(T, U32.to_nat(P.Para.max()), ps)
) -> Pair(Laws.tiled(T, lo, ps), nxt(T, lo, ps)):
  match ps:
    case Nil{}:
      (gap_end(T, lo, tl), Unit{})
    case Con{p, +rest}:
      match p:
        case P.Para{+n, +s, +e, +t}:
          match tl:
            case (+ks, (+ke, (es, (ee, (gE, (dd, (qq, tr))))))):
              match a:
                case (gp, ar):
                  tiled_fin0(rest, T, fits, n, s, e, t, lo, ks, ke, es, ee, gE, dd, qq,
                    pfacts_of(T, fits, P.Para{n, s, e, t}, gp),
                    tiled_of(rest, T, fits, ke, tr, ar))

# the first half of a pair
def tiled_fst(
  -T: String,
  -ps: List<&2, P.Para>,
  r: Pair(Laws.tiled(T, 0n, ps), nxt(T, 0n, ps))
) -> Laws.tiled(T, 0n, ps):
  match r:
    case (x, _h):
      x

def Laws.para_nonblank(text, p, h):
  nonblank_of_good(text, U32.to_nat(P.Para.max()), p, M6.good_split(text, p, h))

def Laws.para_cover(text, fits, i, c, hc, hs):
  cover_law(text, fits, i, c, hs, get_drop(text, i, c, hc))

def Laws.para_tiled(text, fits):
  tiled_fst(text, P.Para.split(text),
    tiled_of(P.Para.split(text), text, fits, 0n, split_tile(text, M6.split_ok(text)),
      M6.split_all(text, M6.split_ok(text))))
