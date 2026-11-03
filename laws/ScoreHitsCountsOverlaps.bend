import Base
import ../src/excerpt.bend as E
import ../src/score.bend as Sc
import ./defs/Specification.bend as D1

# LAW: an example: of two spans, the one the excerpt overlaps is recalled
law score_hits_example:
  for u: Unit
  {Sc.Score.hits([E.Gold{"book:x/y", 150, 160}, E.Gold{"book:x/y", 300, 400}],
      D1.page("book:x/y"))
    == 1n : Nat}
