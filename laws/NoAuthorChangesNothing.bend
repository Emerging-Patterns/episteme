# With no `--author` nothing changes: `Filter.who(None)` names no author,
# and for a question that names none `Filter.by([], xs)` is `xs`, and the
# run notice is the body it was before authors could be named
# (laws/RunNoticeNamesShards.bend, law notice_names_shards).
import Base
import ../src/filter.bend as F
import ../src/excerpt.bend as E

# LAW: no --author names no author
law author_absent_value:
  for u: Unit
  {F.Filter.who(None{}) == [] : List<&2, String>}

# LAW: a question that names no author keeps every excerpt, in order
law author_absent_excerpts:
  for xs: List<&2, E.Ex>
  {F.Filter.by([], xs) == xs : List<&2, E.Ex>}
