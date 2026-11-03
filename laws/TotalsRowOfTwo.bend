import Base
import ../src/score.bend as Sc

# LAW: an example: the totals row of two questions
law totals_line_example:
  for u: Unit
  {Sc.Score.line("x", Sc.Score.total([
      Sc.Row{"a", 1n, 2n, 76n, 0n, 1n, 900n, 5n, 10n},
      Sc.Row{"b", 2n, 2n, 0n, 3n, 0n, 450n, 0n, 0n}]), 38n)
    == "| x | 2 | 75.0% | 3 | 4 | 100 | 0.4 | 0.9 | 500 | 1 | 3 |" : String}
