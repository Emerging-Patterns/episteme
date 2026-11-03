import Base
import ../src/excerpt.bend as E
import ./defs/Specification.bend as D1

# LAW: an example: spans that only touch the paragraph, ending where it
# starts or starting where it ends, are not recalled
law recall_touch_example:
  for u: Unit
  {(E.Excerpt.recalled(E.Gold{"book:x/y", 50, 100}, D1.page("book:x/y")),
    E.Excerpt.recalled(E.Gold{"book:x/y", 200, 250}, D1.page("book:x/y")))
    == (False{}, False{}) : Bool & Bool}
