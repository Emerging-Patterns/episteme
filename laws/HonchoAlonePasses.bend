import Base
import ../src/filter.bend as F

# LAW: an example: exact chat:honcho alone passes
law check_honcho_example:
  for u: Unit
  {F.Filter.check([F.Exact{"chat:honcho"}])
    == Done{Unit{}}
    : Result<&2, &2, String, Unit>}
