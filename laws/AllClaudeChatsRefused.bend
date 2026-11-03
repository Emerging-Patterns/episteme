import Base
import ../src/filter.bend as F

# LAW: an example: chat:claude/, every Claude chat, is refused
law check_all_chats_example:
  for u: Unit
  {F.Filter.check(F.Filter.parse(["chat:claude/"]))
    == Fail{"a filter is required, and a chat filter must name a project; run \"episteme sources\" to list them"}
    : Result<&2, &2, String, Unit>}
