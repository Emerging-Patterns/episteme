import Base
import ../src/honcho.bend as H
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# LAW: an example: the ids of a session list page
law hon_ids_example:
  for u: Unit
  {H.Honcho.ids(Maybe.default(&2, List<&2, Value.Json>,
      H.Honcho.items("{\"items\":[{\"id\":\"projects\",\"metadata\":{}},{\"metadata\":{}},{\"id\":\"s-2\"}],\"total\":3,\"page\":1,\"size\":100,\"pages\":1}"), []))
    == ["projects", "s-2"] : List<&2, String>}
