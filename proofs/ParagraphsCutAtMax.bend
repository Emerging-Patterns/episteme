# proofs of laws/ParagraphsCutAtMax.bend
import Base
import ../src/para.bend as P
import ../laws/ParagraphsCutAtMax.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/NatArithmetic.bend as M1
import ./lemmas/PackingSteps.bend as M2
import ./lemmas/ParagraphScan.bend as M3

# where a paragraph of text t ends, at m: its run ends, or it is cut
def endc(T: String, cap: Nat, m: Nat, t: String) -> Type:
  Or(M2.rend(T, m), M2.cutc(T, cap, m, t))

# a told-apart end is an end
def endr_endc(-T: String, -cap: Nat, -m: Nat, -t: String, x: M2.endr(T, cap, m, t)) -> endc(T, cap, m, t):
  match x:
    case Inl{y}:
      match y:
        case Inl{z}:
          match z:
            case (_eb, r):
              Inl{r}
        case Inr{f}:
          match f:
            case (h, (r, (e1, (e2, (e3, _e4))))):
              Inl{Inr{(h, (r, (e1, (e2, e3))))}}
    case Inr{c}:
      Inr{c}

# a good paragraph is at most cap long
def max_of_good(
  -T: String,
  -cap: Nat,
  p: P.Para,
  g: M2.good(T, cap, p)
) -> {Nat.is_le(String.length(D1.para.text(p)), cap) == True{} : Bool}:
  match p:
    case P.Para{_n, _s, _e, _t}:
      match g:
        case (_o, (le, _nb)):
          le

# where a good paragraph ends, told apart, read at its U32 end offset
def endr_of_good(
  -T: String,
  -cap: Nat,
  fits: M1.rt(String.length(T)),
  p: P.Para,
  g: M2.good(T, cap, p)
) -> M2.endr(T, cap, U32.to_nat(D1.para.end(p)), D1.para.text(p)):
  match p:
    case P.Para{_n, _s, e, t}:
      match g:
        case (o, _rest):
          match o:
            case (+k, (+l, (_es, (ee, (_et, (qe, ec)))))):
              match qe:
                case (+q, eq):
                  %Equal.sym(Nat, U32.to_nat(e), Nat.add(l, k),
                      Equal.trans(Nat, U32.to_nat(e), U32.to_nat(U32.from_nat(Nat.add(l, k))),
                        Nat.add(l, k),
                        Equal.cong(U32, Nat, z => U32.to_nat(z), e,
                          U32.from_nat(Nat.add(l, k)), ee),
                        M3.rt_end(T, l, k, q, eq, fits)))
                    : M2.endr(T, cap, _, t)
                  ec

# where a good paragraph ends, read at its U32 end offset
def cut_of_good(
  -T: String,
  -cap: Nat,
  fits: M1.rt(String.length(T)),
  p: P.Para,
  g: M2.good(T, cap, p)
) -> endc(T, cap, U32.to_nat(D1.para.end(p)), D1.para.text(p)):
  endr_endc(T, cap, U32.to_nat(D1.para.end(p)), D1.para.text(p),
    endr_of_good(T, cap, fits, p, g))

def Laws.para_max(text, p, h):
  max_of_good(text, U32.to_nat(P.Para.max()), p, M3.good_split(text, p, h))

def Laws.para_cut(text, fits, p, h):
  cut_of_good(text, U32.to_nat(P.Para.max()), fits, p, M3.good_split(text, p, h))
