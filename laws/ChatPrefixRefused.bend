import Base
import ../src/filter.bend as F

# LAW: an example: the prefix chat: is refused
law check_chat_prefix_example:
  for u: Unit
  {F.Filter.check([F.Prefix{"chat:"}])
    == Fail{"a filter is required, and a chat filter must name a project; run \"episteme sources\" to list them"}
    : Result<&2, &2, String, Unit>}
