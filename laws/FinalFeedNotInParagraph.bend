import Base
import ../src/para.bend as P

# LAW: an example: a final line feed is no part of the paragraph before it
law para_example_feed:
  for u: Unit
  {P.Para.split("a\n") == [P.Para{1, 0, 1, "a"}] : List<&2, P.Para>}
