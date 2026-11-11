# `Score.cover(g, xs)` is how many code points of the gold span `g` the
# excerpts `xs` return: for each excerpt whose record has the span's source,
# and each of its paragraphs, the code points from the later of the two
# starts to the earlier of the two ends, by whole-file offsets as
# laws/RecalledMeansOverlap.bend reads them. No excerpts return none, and
# what two lists of excerpts return together is what each returns, added:
# nothing is counted for an excerpt beyond its own paragraphs.
#
# The eval prints coverage beside recall: `Score.covered(gs, xs)`, the sum of
# `Score.cover` over a question's gold spans, over `Score.span(gs)`, the
# spans' code points. Recall counts a span as recalled when one paragraph
# overlaps it at all (laws/RecalledMeansOverlap.bend); coverage says how
# much of it came back, so a change that returns smaller pieces of more
# spans shows as such. A code point is counted once when the
# excerpts hold no paragraph twice, as a run's merged excerpts do; that is
# trusted here, not proved.
import Base
import ../src/excerpt.bend as E
import ../src/score.bend as Sc

# LAW: no excerpts return nothing of a gold span
law cover_none:
  for g: E.Gold
  {Sc.Score.cover(g, []) == 0n : Nat}

# LAW: two lists of excerpts together return of a gold span what each returns, added
law cover_append:
  for g: E.Gold
  for xs: List<&2, E.Ex>
  for ys: List<&2, E.Ex>
  {Sc.Score.cover(g, List.append(&2, E.Ex, xs, ys))
    == Nat.add(Sc.Score.cover(g, xs), Sc.Score.cover(g, ys)) : Nat}
