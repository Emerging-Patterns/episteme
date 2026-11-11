# `Score.hits(gs, xs)` is the number of spans `g` of `gs` for which
# `Excerpt.recalled(g, xs)` holds, so it is at most the length of `gs`: recall
# never exceeds 1.
#
# `src/score.bend` scores the eval. A question's gold spans are `Gold{source,
# start, end}` (laws/RecalledMeansOverlap.bend), and `Score.hits(gs, xs)`
# counts the spans of `gs` that `Excerpt.recalled` holds for over the
# question's merged excerpts `xs`. A question's result is `Row{id, hit, gold,
# chars, unknown, failed, ms, prompt_n, prompt_ms, cover, span}`: the gold
# spans recalled and in all, the code points of the excerpts' paragraph texts
# (`Score.chars`), the unknown labels, the failed shards, the wall
# milliseconds, the sums of its reads' `prompt_n` and `prompt_ms`, and the
# gold spans' code points returned and in all
# (laws/CoverageAddsOverExcerpts.bend).
# `Score.total(rows)` counts the rows, sums each count over them, and takes
# the wall times' lower median `Score.p50` (the element at index `(n - 1) / 2`
# of the times sorted ascending, 0 for no rows) and maximum `Score.max` (0 for
# no rows). `Score.ratio(a, b)` is `a / b` rounded down. The totals row gives
# recall as `Score.ratio(1000 * hit, gold)` per mille, the mean excerpt tokens
# as `Score.ratio(100 * chars, per * questions)` at `per / 100` characters a
# token (`chars_per_token`), prefill tokens a second as `Score.ratio(1000
# * prompt_n, prompt_ms)`, and coverage as `Score.ratio(1000 * cover, span)`
# per mille. Closed examples check the hits of one recalled and
# one missed span, the median and maximum of `[9, 1, 5, 3]` (3 and 9) and of
# no times (0 and 0), and the totals row of two rows; no guarantee rests on
# them.
import Base
import ../src/excerpt.bend as E
import ../src/score.bend as Sc

# how many spans of gs the excerpts recall: one for each g that
# Excerpt.recalled holds for
def recalled.count(gs: List<&2, E.Gold>, +xs: List<&2, E.Ex>) -> Nat:
  match gs:
    case Nil{}:
      0n
    case Con{g, +rest}:
      Bool.pick(Nat, E.Excerpt.recalled(g, xs), 1n+recalled.count(rest, xs),
        recalled.count(rest, xs))

# LAW: a question's hits are the gold spans recalled
law hits_count:
  for gs: List<&2, E.Gold>
  for +xs: List<&2, E.Ex>
  {Sc.Score.hits(gs, xs) == recalled.count(gs, xs) : Nat}

# LAW: a question never recalls more spans than it has: recall is at most 1
law hits_le:
  for gs: List<&2, E.Gold>
  for +xs: List<&2, E.Ex>
  {Nat.is_le(Sc.Score.hits(gs, xs), List.length(&2, E.Gold, gs)) == True{} : Bool}
