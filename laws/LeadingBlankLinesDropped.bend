import Base
import ../src/para.bend as P

# LAW: an example: leading line feeds and a whitespace line are no part of
# the paragraph after them
law para_example_lead:
  for u: Unit
  {P.Para.split("\n  \na") == [P.Para{1, 4, 5, "a"}] : List<&2, P.Para>}
