import Base
import ../src/filter.bend as F

# LAW: an example: a month of one digit is malformed
law since_month_example:
  for u: Unit
  {F.Filter.since("2026-1-24") == None{} : Maybe<&2, String>}
