# With no `--since` nothing changes: `Filter.since.arg(None)` is `Done{None}`,
# `Filter.recent(None, ss)` is `ss` and `Filter.after(None, xs)` is `xs`.
import Base
import ../src/shard.bend as S
import ../src/filter.bend as F
import ../src/excerpt.bend as E

# LAW: no --since reads as no since
law since_absent_arg:
  for u: Unit
  {F.Filter.since.arg(None{}) == Done{None{}}
    : Result<&2, &2, String, Maybe<&2, String>>}

# LAW: no since keeps every shard, in order
law since_absent_shards:
  for ss: List<&2, S.Shard>
  {F.Filter.recent(None{}, ss) == ss : List<&2, S.Shard>}

# LAW: no since keeps every excerpt, in order
law since_absent_excerpts:
  for xs: List<&2, E.Ex>
  {F.Filter.after(None{}, xs) == xs : List<&2, E.Ex>}
