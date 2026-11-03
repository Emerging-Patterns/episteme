# Against the model of a session's list, a read from the count of messages
# read before gives exactly the messages added since, across any number of
# pages: `Honcho.walk(1 + length(xs ++ ys), xs ++ ys,
# Honcho.place(length(xs)))` is `ys`, so a message read is never read twice
# and one added later is never skipped. That Honcho serves its list as the
# model does is src/conn/honcho.bend's assumption.
import Base
import ../src/honcho.bend as H
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# LAW: a read of xs ++ ys from the count of xs gives exactly ys, across
# pages
law read_across:
  for +xs: List<&2, Value.Json>
  for +ys: List<&2, Value.Json>
  {H.Honcho.walk(1n+List.length(&2, Value.Json, List.append(&2, Value.Json, xs, ys)),
      List.append(&2, Value.Json, xs, ys), H.Honcho.place(List.length(&2, Value.Json, xs)))
    == ys : List<&2, Value.Json>}
