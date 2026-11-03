import Base
import ../src/filter.bend as F

# LAW: an example: a time without seconds is malformed
law since_short_example:
  for u: Unit
  {F.Filter.since("2026-10-24T05:06Z") == None{} : Maybe<&2, String>}
