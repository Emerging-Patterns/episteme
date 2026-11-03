import Base
import ../src/excerpt.bend as E
import ./defs/Specification.bend as D1

# LAW: an example: an overlapping span of another source is not recalled
law recall_source_example:
  for u: Unit
  {E.Excerpt.recalled(E.Gold{"book:x/z", 120, 130}, D1.page("book:x/y"))
    == False{} : Bool}
