import Base
import ../src/honcho.bend as H
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# LAW: an example: a text that is not a page has no items
law hon_items_example:
  for u: Unit
  {H.Honcho.items("{\"detail\":\"Not Found\"}") == None{}
    : Maybe<&2, List<&2, Value.Json>>}
