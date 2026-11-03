import Base
import ../src/filter.bend as F

# LAW: an example: a full time is kept as it is
law since_time_example:
  for u: Unit
  {F.Filter.since("2026-10-24T05:06:07.890Z") == Some{"2026-10-24T05:06:07.890Z"}
    : Maybe<&2, String>}
