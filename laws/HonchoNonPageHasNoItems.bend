import Base
import ../src/honcho.bend as H
import ezjson@1.2.0.0/src/value.bend as Value

# LAW: an example: a text that is not a page has no items
law hon_items_example:
  for u: Unit
  {H.Honcho.items("{\"detail\":\"Not Found\"}") == None{}
    : Maybe<&2, List<&2, Value.Json>>}
