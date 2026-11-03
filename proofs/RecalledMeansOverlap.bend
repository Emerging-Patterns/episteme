# proofs of laws/RecalledMeansOverlap.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/excerpt.bend as E
import ../laws/RecalledMeansOverlap.bend as Laws
import ./lemmas/OffsetsHeld.bend as M1

# the code's overlap test is the specification's
law hit_eq:
  for +lo: U32
  for +hi: U32
  for ps: List<&2, P.Para>
  {E.Excerpt.hit(lo, hi, ps) == Laws.struck(lo, hi, ps) : Bool}

def hit_eq(lo, hi, ps):
  match ps:
    case Nil{}:
      {==}
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, +start, +end, _text}:
          M1.any_if_or(Bool.and(U32.is_lt(start, hi), U32.is_lt(lo, end)),
            E.Excerpt.hit(lo, hi, rest), Laws.struck(lo, hi, rest),
            hit_eq(lo, hi, rest))

# the code's search over excerpts is the specification's
law found_eq:
  for +src: String
  for +lo: U32
  for +hi: U32
  for xs: List<&2, E.Ex>
  {E.Excerpt.found(src, lo, hi, xs) == Laws.found(E.Gold{src, lo, hi}, xs) : Bool}

def found_eq(src, lo, hi, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{x, +rest}:
      match x:
        case E.Ex{rec, +paras}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +rps, +ptr}:
              %Equal.sym(Bool, E.Excerpt.hit(lo, hi, paras),
                Laws.struck(lo, hi, paras), hit_eq(lo, hi, paras))
                : {List.any.if(_u => E.Excerpt.found(src, lo, hi, rest),
                  Bool.and(String.eq(source, src), _))
                  == Laws.found(E.Gold{src, lo, hi}, E.Ex{R.Record{id, ts, source,
                    author, thread, parent, rps, ptr}, paras} <> rest) : Bool}
              M1.any_if_or(Bool.and(String.eq(source, src), Laws.struck(lo, hi, paras)),
                E.Excerpt.found(src, lo, hi, rest),
                Laws.found(E.Gold{src, lo, hi}, rest), found_eq(src, lo, hi, rest))

def Laws.recalled_overlap(g, xs):
  match g:
    case E.Gold{+source, +start, +end}:
      found_eq(source, start, end, xs)
