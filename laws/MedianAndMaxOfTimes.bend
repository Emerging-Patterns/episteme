import Base
import ../src/score.bend as Sc

# LAW: an example: the lower median and the maximum of four times and of
# none
law p50_example:
  for u: Unit
  {(Sc.Score.p50([9n, 1n, 5n, 3n]), Sc.Score.max([9n, 1n, 5n, 3n]),
      Sc.Score.p50([]), Sc.Score.max([]))
    == (3n, 9n, 0n, 0n) : Nat & Nat & Nat & Nat}
