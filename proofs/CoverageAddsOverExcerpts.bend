# proofs of laws/CoverageAddsOverExcerpts.bend
import Base
import ../src/excerpt.bend as E
import ../src/score.bend as Sc
import ../laws/CoverageAddsOverExcerpts.bend as Laws
import ./lemmas/NatArithmetic.bend as M1

def Laws.cover_none(g):
  match g:
    case E.Gold{_source, _start, _end}:
      {==}

# one excerpt's count ahead of the rest's sum is the sum with it ahead of the first part
def cover_step(
  +h: Nat,
  +a: Nat,
  +b: Nat,
  -c: Nat,
  e: {c == Nat.add(a, b) : Nat}
) -> {Nat.add(h, c) == Nat.add(Nat.add(h, a), b) : Nat}:
  Equal.trans(Nat, Nat.add(h, c), Nat.add(h, Nat.add(a, b)), Nat.add(Nat.add(h, a), b),
    Equal.cong(Nat, Nat, y => Nat.add(h, y), c, Nat.add(a, b), e),
    Equal.sym(Nat, Nat.add(Nat.add(h, a), b), Nat.add(h, Nat.add(a, b)), M1.add_assoc(h, a, b)))

# Score.cover.in adds over appended excerpts
def cover_in_append(
  +src: String,
  +lo: U32,
  +hi: U32,
  xs: List<&2, E.Ex>,
  +ys: List<&2, E.Ex>
) -> {Sc.Score.cover.in(src, lo, hi, List.append(&2, E.Ex, xs, ys))
    == Nat.add(Sc.Score.cover.in(src, lo, hi, xs), Sc.Score.cover.in(src, lo, hi, ys)) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case Con{x, +rest}:
      match x:
        case E.Ex{rec, paras}:
          cover_step(
            Sc.Score.cover.if(String.eq(E.Excerpt.source(rec), src), lo, hi, paras),
            Sc.Score.cover.in(src, lo, hi, rest), Sc.Score.cover.in(src, lo, hi, ys),
            Sc.Score.cover.in(src, lo, hi, List.append(&2, E.Ex, rest, ys)),
            cover_in_append(src, lo, hi, rest, ys))

def Laws.cover_append(g, xs, ys):
  match g:
    case E.Gold{source, start, end}:
      cover_in_append(source, start, end, xs, ys)
