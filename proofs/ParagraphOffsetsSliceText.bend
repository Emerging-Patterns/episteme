# proofs of laws/ParagraphOffsetsSliceText.bend
import Base
import ../src/para.bend as P
import ../laws/ParagraphOffsetsSliceText.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/NatArithmetic.bend as M1
import ./lemmas/PackingSteps.bend as M2
import ./lemmas/ParagraphScan.bend as M3

# --- numbering ---

# numbering from i gives i, i+1, ... in order
law number_upto:
  for xs: List<&2, P.Para>
  for +i: U32
  {D1.numbers(P.Para.number(xs, i))
    == D1.upto(List.length(&2, P.Para, P.Para.number(xs, i)), i)
    : List<&2, U32>}

def number_upto(xs, i):
  match xs:
    case Nil{}:
      {==}
    case Con{p, rest}:
      match p:
        case P.Para{_n, s, e, t}:
          Equal.cong(List<&2, U32>, List<&2, U32>, ys => i <> ys,
            D1.numbers(P.Para.number(rest, U32.inc(i))),
            D1.upto(List.length(&2, P.Para, P.Para.number(rest, U32.inc(i))),
              U32.inc(i)),
            number_upto(rest, U32.inc(i)))

def Laws.para_numbered(text):
  +cap = U32.to_nat(P.Para.max())
  number_upto(P.Para.go(text, cap,
    P.Scan{0, P.Shut{}, P.Line{text, 0, 0n, cap, True{}}}), 1)

# a good paragraph's offsets slice T to its text, when T's length survives
# a round trip through U32
def offsets_of_good(
  -T: String,
  -cap: Nat,
  fits: M1.rt(String.length(T)),
  p: P.Para,
  g: M2.good(T, cap, p)
) -> {D1.slice(T, U32.to_nat(D1.para.start(p)), U32.to_nat(D1.para.end(p)))
  == D1.para.text(p) : String}:
  match p:
    case P.Para{_n, s, e, t}:
      match g:
        case (o, _rest):
          match o:
            case (+k, (+l, (es, (ee, (et, (qe, _ec)))))):
              match qe:
                case (+q, eq):
                  M3.offsets_fin(T, l, k, s, e, t, es, ee, et,
                    M3.rt_end(T, l, k, q, eq, fits))

def Laws.para_offsets(text, fits, p, h):
  offsets_of_good(text, U32.to_nat(P.Para.max()), fits, p,
    M3.good_split(text, p, h))
