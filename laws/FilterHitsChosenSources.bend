# `Filter.hits(f, sources)` is True exactly when some source equals an exact
# selector of `f` or starts with a prefix selector of `f`; and
# `Filter.reads(f, Shard.dir(s))`, the test `Store.shards` runs on each source
# directory's name, is `Filter.hits(f, [s])`, so `ask` reads a source's
# directory exactly when the filter hits a shard of that one source.
#
# A question's filter, in `src/filter.bend`, is a list of selectors, each
# `Exact{text}` or `Prefix{text}`. `Filter.parse` reads the `--filter` values:
# each is split at commas, each piece is trimmed of surrounding whitespace,
# empty pieces are dropped, and a piece that ends in `/` is a prefix, any
# other an exact value; a closed example checks this and no guarantee rests on
# it. `Filter.hits(f, sources)` says whether a shard with those `sources` is
# read; `Filter.reads(f, name)` is what `ask` runs, on the name of each source
# directory: the name read back with `Shard.undir`, never read when it is no
# source's, else `Filter.picks(f, s)` of its source `s`. `Filter.check(f)` is
# that a question about chats must name a project, so a filter
# that is empty, or that holds a selector meaning every Claude chat (exact
# `chat:claude`, prefix `chat:`, prefix `chat:claude/` or prefix `""`), is
# refused with the text `a filter is required, and a chat filter must name a
# project; run "episteme sources" to list them`, and any other filter,
# `chat:honcho` alone included, passes. Closed examples check that
# `book:venaya/` hits `[book:venaya/b1]` and misses `[book:venayaX]`, that
# `chat:claude/home-noah-projects-bend` and `chat:honcho` pass the check, and
# that `chat:claude/` and the hand-built selectors exact `chat:claude`, prefix
# `chat:` and prefix `""` are refused with the refusal text.
import Base
import ../src/shard.bend as S
import ../src/filter.bend as F
import ./defs/SourceSelection.bend as D1

# LAW: a filter hits a shard exactly when one of its selectors selects one
# of the shard's sources
law filter_hits:
  for +sels: List<&2, F.Sel>
  for srcs: List<&2, String>
  {F.Filter.hits(sels, srcs) == D1.overlaps(sels, srcs) : Bool}

# LAW: ask reads a source's directory exactly when the filter hits a shard
# of that one source: Filter.reads, which Store.shards runs on each
# directory name, of Shard.dir(src) is Filter.hits of [src]
law reads_dir:
  for +sels: List<&2, F.Sel>
  for +src: String
  {F.Filter.reads(sels, S.Shard.dir(src)) == F.Filter.hits(sels, [src]) : Bool}
