import Base
import ../src/filter.bend as F

# LAW: an example: exact chat:claude is refused
law check_exact_claude_example:
  for u: Unit
  {F.Filter.check([F.Exact{"chat:claude"}])
    == Fail{"a filter is required, and a chat filter must name a project; run \"episteme sources\" to list them"}
    : Result<&2, &2, String, Unit>}
