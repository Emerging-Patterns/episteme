import Base
import ../src/para.bend as P

# LAW: an example: blank lines between two lines make two paragraphs, and
# the final line feed is no part of the last one. A closed example: its
# binder is no input, since bolt's closed rule takes no law without one
law para_example:
  for u: Unit
  {P.Para.split("a\n\n\nb c\n")
    == [P.Para{1, 0, 1, "a"}, P.Para{2, 4, 7, "b c"}] : List<&2, P.Para>}
