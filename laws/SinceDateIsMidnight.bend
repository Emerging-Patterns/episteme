import Base
import ../src/filter.bend as F

# LAW: an example: a date is its midnight UTC.
law since_date_example:
  for u: Unit
  {F.Filter.since("2026-10-24") == Some{"2026-10-24T00:00:00.000Z"}
    : Maybe<&2, String>}
