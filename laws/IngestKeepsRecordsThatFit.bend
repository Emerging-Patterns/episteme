# `Record.fits(r)` is True exactly when `r`'s id, ts and source are not empty
# and its header line is at most `Para.max()` code points;
# `Record.fitting(xs)` keeps a record of `xs` exactly when it fits, and keeps
# nothing else.
#
# What ingest appends and what it writes, in `src/record.bend` and
# `src/shard.bend`. `Record.fits(r)` says whether ingest may append a record:
# its id, ts and source are not empty, as `Record.of_line` asks, and its
# header line is at most `Para.max()` code points, as
# laws/FrozenShardsFitCap.bend assumes. `Record.fitting(xs)` is the records of
# `xs` that fit, in order. Ingest does no id dedup: a connector's ids are
# deterministic from a record's native identity and its cursor says what it
# has given, and the cursor is stored in the same log batch as the records it
# covers (src/store.bend), so the two cannot disagree; a connector that gives
# each record once keeps one id to one ts, which merge relies on.
# `Shard.extend(cap, t, ys)` resumes packing: a tail is the open shard a pack
# ends with, so `Shard.run` goes on from its items and their size and numbers
# the shards from `t`'s number, and no frozen shard is packed again. By
# laws/ExtendResumesPack.bend, a source's directory whose tail has covered
# every log batch, extended batch by batch in log order with that source's
# records, holds exactly `Shard.pack(cap, 1, Shard.only(s, log))`:
# laws/SourceSplitIsOnePass.bend splits `Shard.only(s, log ++ batch)` into
# `Shard.only(s, log) ++ Shard.only(s, batch)`, and every source with a record
# in the batch is among `Shard.keys(batch)`, so a source new in a batch gets
# its shards too. Ingest splits each batch by source in one pass,
# `Shard.parts(xs)`: one `Part{src, recs}` per source, sorted by source, put
# in place by walking the parts, and `Shard.part(s, ps)` is the records of the
# parts of `s`; by laws/SourceSplitIsOnePass.bend that is `Shard.only(s, xs)`,
# so the split costs one pass a batch rather than one filter per source.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2

# True when a text is not empty
def nonempty(str: String) -> Bool:
  match str:
    case SNil{}:
      False{}
    case SCon{_head, _tail}:
      True{}

# LAW: Record.fits is True exactly when a record's id, ts and source are
# not empty and its header line is at most Para.max() code points
law fits_spec:
  for rec: R.Record
  {R.Record.fits(rec) == Bool.and(nonempty(D2.rec.id(rec)),
    Bool.and(nonempty(D2.rec.ts(rec)), Bool.and(nonempty(D2.rec.source(rec)),
      Nat.is_le(D2.rec.head(rec), U32.to_nat(P.Para.max()))))) : Bool}

# LAW: every record Record.fitting keeps is one it was given
law fitting_from:
  for xs: List<&2, R.Record>
  for r: R.Record
  for h: D1.Elem(R.Record, r, R.Record.fitting(xs))
  D1.Elem(R.Record, r, xs)

# LAW: every record Record.fitting keeps fits
law fitting_fits:
  for xs: List<&2, R.Record>
  for r: R.Record
  for h: D1.Elem(R.Record, r, R.Record.fitting(xs))
  {R.Record.fits(r) == True{} : Bool}

# LAW: Record.fitting keeps every record it is given that fits
law fitting_all:
  for xs: List<&2, R.Record>
  for r: R.Record
  for h: D1.Elem(R.Record, r, xs)
  for ok: {R.Record.fits(r) == True{} : Bool}
  D1.Elem(R.Record, r, R.Record.fitting(xs))
