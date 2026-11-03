# `Score.ratio(a, b)` is `a / b` rounded down, and 0 when `b` is 0, so a run
# with no questions, no gold or no prompt time reports 0 and never fails.
import Base
import ../src/score.bend as Sc

# LAW: a ratio over 0 is 0
law ratio_zero:
  for num: Nat
  {Sc.Score.ratio(num, 0n) == 0n : Nat}

# LAW: a ratio is rounded down: times its denominator it is at most its
# numerator
law ratio_div:
  for +num: Nat
  for +k: Nat
  {Nat.is_le(Nat.mul(Sc.Score.ratio(num, 1n+k), 1n+k), num) == True{} : Bool}
