# `Shard.only(s, xs)` keeps exactly the records of `xs` whose source is `s`,
# and every item of every shard of `pack(cap, n, Shard.only(s, xs))` is of a
# record whose source is `s`: a shard holds one source.
#
# Shards are split by source. `Shard.only(s, xs)` is the records of `xs` whose source is `s`, in
# order, and the shards of source `s` are `Shard.pack(cap, 1, Shard.only(s,
# log))`, so each shard holds one source and each source has its own numbering
# from 1 and its own tail; `pack` itself is unchanged and its guarantees hold
# for each source. `Shard.keys(xs)` is the sorted distinct sources of `xs`. A
# source's shards live in a directory named `Shard.dir(s)`: the source with
# `%`, `/` and `.` escaped as `%25`, `%2F` and `%2E`, readable by a person,
# never `.` or `..` and never holding `/`; `Shard.undir` reads a name back,
# None for a name with a bare `/` or `.` or a `%` not followed by `25`, `2F`
# or `2E`, so `tail.json` and the other files beside the source directories
# are no source's. Closed examples check that
# `chat:claude/home-noah-projects-bend` is named
# `chat:claude%2Fhome-noah-projects-bend` and that `tail.json` is no source's
# name, and no guarantee rests on them. A name's length is not bounded: a
# source longer than the file system's name limit (255 bytes on Linux, after
# escapes) makes the write of its shards stop with an error.
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2

# True when the record's source is src
def of_src(+src: String, record: R.Record) -> Bool:
  String.eq(D2.rec.source(record), src)

# LAW: every item of every shard packed from Shard.only(src, xs) is of a
# record whose source is src: a shard holds one source
law one_source:
  for +cap: U32
  for +n: U32
  for +src: String
  for +xs: List<&2, R.Record>
  for s: S.Shard
  for hs: D1.Elem(S.Shard, s, S.Shard.pack(cap, n, S.Shard.only(src, xs)))
  for it: S.Item
  for hi: D1.Elem(S.Item, it, D2.shard.items(s))
  {of_src(src, D2.item.rec(it)) == True{} : Bool}

# LAW: every record Shard.only(src, xs) keeps is one of xs, of source src
law only_from:
  for +src: String
  for xs: List<&2, R.Record>
  for r: R.Record
  for h: D1.Elem(R.Record, r, S.Shard.only(src, xs))
  Pair(D1.Elem(R.Record, r, xs), {of_src(src, r) == True{} : Bool})

# LAW: Shard.only(src, xs) keeps every record of xs of source src
law only_all:
  for +src: String
  for xs: List<&2, R.Record>
  for r: R.Record
  for h: D1.Elem(R.Record, r, xs)
  for e: {of_src(src, r) == True{} : Bool}
  D1.Elem(R.Record, r, S.Shard.only(src, xs))
