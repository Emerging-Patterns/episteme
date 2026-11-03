# `Filter.check(f)` refuses, with the refusal text above, exactly the empty
# filter and the filters holding a chat-wide selector (exact `chat:claude`,
# prefix `chat:`, prefix `chat:claude/`, prefix `""`), and passes every other
# filter.
import Base
import ../src/filter.bend as F
import ./defs/Specification.bend as D1

# the check's answer: the refusal, or Done
def verdict(bad: Bool) -> Result<&2, &2, String, Unit>:
  match bad:
    case True{}:
      Fail{"a filter is required, and a chat filter must name a project; run \"episteme sources\" to list them"}
    case False{}:
      Done{Unit{}}

# LAW: the check refuses exactly the empty filter and the filters holding a
# chat-wide selector, with the refusal text, and passes every other filter
law filter_check:
  for sels: List<&2, F.Sel>
  {F.Filter.check(sels) == verdict(D1.refused(sels))
    : Result<&2, &2, String, Unit>}
