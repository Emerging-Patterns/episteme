# `Honcho.step(Place{d, skip}, items)` is `Step{Honcho.fresh(skip, items),
# Some{Place{d + 1, 0}}}` when `items` is full (`Honcho.size()` items), and
# `Step{Honcho.fresh(skip, items), None}` otherwise: only the first page of a
# read skips.
import Base
import ../src/honcho.bend as H
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# LAW: a full page goes on at the next page, from its start
law step_full:
  for d: Nat
  for skip: Nat
  for +items: List<&2, Value.Json>
  for h: {H.Honcho.full(items) == True{} : Bool}
  {H.Honcho.step(H.Place{d, skip}, items)
    == H.Step{H.Honcho.fresh(skip, items), Some{H.Place{1n+d, 0n}}} : H.Step}

# LAW: any other page ends the read
law step_part:
  for d: Nat
  for skip: Nat
  for +items: List<&2, Value.Json>
  for h: {H.Honcho.full(items) == False{} : Bool}
  {H.Honcho.step(H.Place{d, skip}, items)
    == H.Step{H.Honcho.fresh(skip, items), None{}} : H.Step}
