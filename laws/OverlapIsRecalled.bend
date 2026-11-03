import Base
import ../src/excerpt.bend as E
import ./defs/Specification.bend as D1

# LAW: an example: a span overlapping the paragraph's last code point is
# recalled
law recall_example:
  for u: Unit
  {E.Excerpt.recalled(E.Gold{"book:x/y", 199, 300}, D1.page("book:x/y"))
    == True{} : Bool}
