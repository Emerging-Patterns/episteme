# `Excerpt.recalled(g, xs)` is True exactly when some excerpt's record has
# source `g.source` and holds a paragraph with `start < g.end` and `g.start <
# end`.
import Base
import ../src/para.bend as P
import ../src/excerpt.bend as E
import ./defs/Specification.bend as D1

# a gold span's source
def gold.source(gold: E.Gold) -> String:
  match gold:
    case E.Gold{source, _start, _end}:
      source

# where a gold span starts in its file
def gold.start(gold: E.Gold) -> U32:
  match gold:
    case E.Gold{_source, start, _end}:
      start

# where a gold span ends in its file, exclusive
def gold.end(gold: E.Gold) -> U32:
  match gold:
    case E.Gold{_source, _start, end}:
      end

# True when some paragraph of ps overlaps the span from lo to hi: start < hi
# and lo < end
def struck(+lo: U32, +hi: U32, ps: List<&2, P.Para>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{+p, tail}:
      Bool.or(Bool.and(U32.is_lt(D1.para.start(p), hi),
        U32.is_lt(lo, D1.para.end(p))), struck(lo, hi, tail))

# True when some excerpt of xs has a record of gold's source and a
# paragraph that overlaps gold
def found(+gold: E.Gold, xs: List<&2, E.Ex>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, tail}:
      Bool.or(Bool.and(String.eq(D1.rec.source(D1.ex.rec(x)), gold.source(gold)),
        struck(gold.start(gold), gold.end(gold), D1.ex.paras(x))), found(gold, tail))

# LAW: a gold span is recalled exactly when some excerpt's record has its
# source and holds a paragraph whose whole-file offsets overlap it
law recalled_overlap:
  for +g: E.Gold
  for xs: List<&2, E.Ex>
  {E.Excerpt.recalled(g, xs) == found(g, xs) : Bool}
