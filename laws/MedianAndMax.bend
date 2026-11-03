# `Score.max(ns)` is at least every element of `ns`; for a non-empty `ns`,
# `Score.p50(ns)` is an element of `ns`, so it is at most `Score.max(ns)`.
import Base
import ../src/score.bend as Sc
import ./defs/ListMembership.bend as D1

# LAW: the largest wall time is at least each of them
law max_ge:
  for ns: List<&2, Nat>
  for +x: Nat
  for h: D1.Elem(Nat, x, ns)
  {Nat.is_ge(Sc.Score.max(ns), x) == True{} : Bool}

# LAW: the median of some wall times is one of them
law p50_elem:
  for +x: Nat
  for +rest: List<&2, Nat>
  D1.Elem(Nat, Sc.Score.p50(x <> rest), x <> rest)

# LAW: the median of some wall times is at most the largest
law p50_le_max:
  for +x: Nat
  for +rest: List<&2, Nat>
  {Nat.is_ge(Sc.Score.max(x <> rest), Sc.Score.p50(x <> rest)) == True{} : Bool}
