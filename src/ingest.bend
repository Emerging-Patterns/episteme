# episteme/src/ingest: append a connector's records to the log and keep
# the shards of the configured size caught up with it, one source's shards
# apart from another's. IO: the trusted shell around Record.fitting,
# Shard.parts and Shard.extend.
#
# Trusted, not proved: Only `episteme ingest` writes the log or the shards.
# Every ingest (a connector, `--all`, `--reshard` or none) first takes the
# lock `<home>/lock`, made with `mkdir` without `-p`, so it fails when the
# lock exists: then the run refuses with exit 1 and `<home>/lock exists:
# another ingest is running; if none is, remove it by hand` on stderr and
# leaves the lock alone. It holds the lock to its end and removes it then, and
# on a failure too: `Store.die` and `Store.exit`, which every failure of the
# IO shell exits through, remove it in an ingest run and in no other run; a
# process killed outright leaves it, to be removed by hand. Holding the lock,
# `episteme ingest --reshard` runs `Ingest.reshard`, and every other ingest
# runs `Ingest.sync(cap)` for the configured size, then its connectors (none
# for a bare `episteme ingest`). `Ingest.sync(cap)` catches the shards of one
# size up with the log: when the highest batch `k` is above the mark, it takes
# the batches above the mark one at a time, in log order, so one batch is in
# memory and never the whole log: it reads the batch, splits it with
# `Shard.parts`, and, for each source of its parts, reads the source's tail
# and its `covered` batch (the empty shard 1 and 0 when there is none) and,
# when the batch is above `covered`, writes `Shard.extend(cap, tail,
# Shard.part(s, parts))`, which is `Shard.only(s, batch)`
# (laws/SourceSplitIsOnePass.bend), with `covered` the batch; then it writes
# the mark, the batch's number, last, before it reads the next. Extending a
# tail batch by batch gives the shards one extension of all of them gives
# (laws/ExtendResumesPack.bend). A crash leaves each
# source's tail and `covered` written together and the mark at or below every
# source's progress, so the next sync packs what is missing and never a batch
# twice. It runs when an ingest starts and in `Ingest.run` and
# `Ingest.reshard`, so a crash between a batch and its shards, a crash between
# a source's shards and the mark, or a size last used before other batches
# were written is packed by the next ingest. Reads never sync:
# `Store.ready(cap)`, run by `episteme sources`, `ask` and `eval` before they
# read the shards, stops with exit 1 and `the <cap>-character shards hold log
# batches up to <mark> of <top>; run episteme ingest` when the mark is below
# the highest batch (a size with no directory has mark 0). A lost tail is not
# repacked: packing on from an empty tail would drop the source's records and
# write over its frozen shard 1, so sync and every read of the shards stop
# with `<dir> has no tail.json; run episteme ingest --reshard`.
# `Ingest.run(conn, xs, c)` syncs (a no-op after the sync the ingest began
# with), reports on stderr each record of `xs` that `Record.fits` rejects, and
# when `Record.fitting(xs)` is not empty appends it as one batch with cursor
# `c`, packs that batch the same way, moves the mark to it, and caches the
# batch number in `state/<conn>.json`; when it is empty it writes nothing. It
# answers how many records it appended. `Ingest.reshard` (`episteme ingest
# --reshard`) removes `shards/<chars>/covered.json`, then `shards/<chars>/`,
# for the configured size and syncs from batch 0, so a reshard stopped half
# way leaves no mark and packs again from batch 1; other sizes are left alone.
# It answers how many shards it wrote, counting the `.json` files of the
# source directories without reading them.
#
# Why it is trusted: It is IO sequencing: no law can state what happens after
# an effect. Every decision it acts on is laws/IngestKeepsRecordsThatFit.bend,
# laws/ExtendResumesPack.bend and `Shard.pack`
# (laws/ShardsCoverEveryParagraph.bend, laws/RecordsSplitOnlyWhenTooBig.bend,
# laws/FrozenShardsFitCap.bend, laws/ShardSourcesSorted.bend,
# laws/FreezingIsStable.bend and laws/OnlyTheLastShardIsOpen.bend). The lock
# is `mkdir`'s, which fails when the directory exists. `tests/smoke.sh` checks
# the source directories and the mark after a first ingest, a run with nothing
# new (no batch, no file written), a lost cursor cache, a crash between a
# batch and its shards (`ask` and `sources` refuse naming `episteme ingest`
# and write nothing, then a bare `episteme ingest` packs it), a source new in
# a batch, a crash between a source's shards and the mark, a lost tail
# (refused by a read and by an ingest's sync with frozen shard 1 untouched,
# then mended by a reshard), a size that missed two batches, a crash in the
# middle of a run followed by a run over another corpus, a second ingest
# refused while the lock exists (the lock left in place, nothing written), and
# the lock removed after an ingest that failed; each ends with no id twice in
# the log, shards byte for byte as a reshard writes them, and every shard
# holding the one source its directory names.
import Base
import ./record.bend as R
import ./shard.bend as S
import ./store.bend as St

# report one record when it does not fit
def Ingest.skip(fits: Bool, rec: R.Record) -> IO(Unit):
  match fits:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      match rec:
        case R.Record{id, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
          IO.print_err("episteme: skipped " ++ id
            ++ ": an empty id, ts or source, or a header longer than PARA_MAX")

# report, on stderr, each record ingest will not append because it does
# not fit (R.Record.fits)
def Ingest.skipped(recs: List<&2, R.Record>) -> IO(Unit):
  match recs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+rec, rest}:
      do IO<Unit>:
        Ingest.skip(R.Record.fits(rec), rec)
        Ingest.skipped(rest)

# the tail on disk and the last batch packed into it, or the empty shard
# 1 and batch 0 when the source has no shards of this size
def Ingest.start(got: Maybe<&2, St.Tail>) -> St.Tail:
  match got:
    case Some{t}:
      t
    case None{}:
      St.Tail{S.Shard{1, [], [], 0, False{}}, 0}

# a log batch's number and its records split by source (Shard.parts)
type Split is Data:
  Split{num: U32, parts: List<&2, S.Part>}

# each batch's records split by source, in one pass a batch
def Ingest.splits(bs: List<&2, St.Numbered>) -> List<&2, Split>:
  match bs:
    case Nil{}:
      []
    case Con{b, rest}:
      match b:
        case St.Numbered{num, recs}:
          Split{num, S.Shard.parts(recs)} <> Ingest.splits(rest)

# the sources of parts put among the sorted distinct sources ys
def Ingest.keys.parts(ps: List<&2, S.Part>, ys: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      ys
    case Con{p, rest}:
      match p:
        case S.Part{src, _recs}:
          Ingest.keys.parts(rest, S.Shard.insert(ys, src))

# the sorted distinct sources of the split batches ss
def Ingest.keys(ss: List<&2, Split>, ys: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}:
      ys
    case Con{sp, rest}:
      match sp:
        case Split{_num, parts}:
          Ingest.keys(rest, Ingest.keys.parts(parts, ys))

# src's records of the split batches ss numbered above covered, in log
# order: Shard.only(src, ...) of each, by laws/SourceSplitIsOnePass.bend
def Ingest.mine(ss: List<&2, Split>, +covered: U32, +src: String) -> List<&2, R.Record>:
  match ss:
    case Nil{}:
      []
    case Con{sp, rest}:
      match sp:
        case Split{num, parts}:
          List.append(&2, R.Record,
            Bool.pick(List<&2, R.Record>, U32.is_gt(num, covered), S.Shard.part(src, parts), []),
            Ingest.mine(rest, covered, src))

# the last of the split batches ss holding a record of src, or last
def Ingest.upto(ss: List<&2, Split>, +src: String, +last: U32) -> U32:
  match ss:
    case Nil{}:
      last
    case Con{sp, rest}:
      match sp:
        case Split{num, parts}:
          Ingest.upto(rest, src,
            Bool.pick(U32, Bool.not(List.is_empty(&2, R.Record, S.Shard.part(src, parts))), num, last))

# extend src's tail with its records recs and write the shards, covering
# batch last, the last batch holding one of them; none writes nothing
def Ingest.put(+recs: List<&2, R.Record>, tail: S.Shard, +cap: U32, +src: String, last: U32) -> IO(Unit):
  match recs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{_rec, _rest}:
      St.Store.put_shards(cap, src, S.Shard.extend(cap, tail, recs), last)

# src's shards caught up from its tail: packing goes on with its records
# of the batches above the last its tail covers
def Ingest.source.at(found: St.Tail, +cap: U32, +src: String, +bs: List<&2, Split>) -> IO(Unit):
  match found:
    case St.Tail{tail, +covered}:
      Ingest.put(Ingest.mine(bs, covered, src), tail, cap, src, Ingest.upto(bs, src, covered))

# each source of srcs caught up with the split batches bs
def Ingest.sources(srcs: List<&2, String>, +cap: U32, +bs: List<&2, Split>) -> IO(Unit):
  match srcs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+src, rest}:
      do IO<Unit>:
        got : Maybe<&2, St.Tail> <- St.Store.tail(cap, src)
        Ingest.source.at(Ingest.start(got), cap, src, bs)
        Ingest.sources(rest, cap, bs)

# pack the batches bs, the log's batches above the mark, the last of them
# top: each batch is split by source in one pass, and every source with a
# record in them is caught up from its own tail,
# whose covered becomes the last batch holding one of its records, then
# the mark moves to top, written last
def Ingest.pack(+cap: U32, bs: List<&2, St.Numbered>, +top: U32) -> IO(Unit):
  +ss = Ingest.splits(bs)
  do IO<Unit>:
    Ingest.sources(Ingest.keys(ss, []), cap, ss)
    St.Store.mark.put(cap, top)

# pack the named log batches one at a time, in log order: each is read,
# packed and the mark moved to it before the next is read, so one batch
# at a time is in memory, never the log
def Ingest.batches(names: List<&2, String>, +dir: String, +cap: U32) -> IO(Unit):
  match names:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+name, rest}:
      do IO<Unit>:
        b : St.Batch <- St.Store.batch.file(dir ++ "/" ++ name)
        +num : U32 = St.Store.num(name)
        Ingest.pack(cap, [St.Numbered{num, St.Store.batch.recs(b)}], num)
        Ingest.batches(rest, dir, cap)

# the shards caught up with the batches above the mark, when there are any
def Ingest.sync.if(behind: Bool, +cap: U32, +mark: U32, +top: U32) -> IO(Unit):
  match behind:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        +dir : String <- St.Store.path("log")
        names : List<&2, String> <- St.Store.names(dir)
        Ingest.batches(St.Store.after(names, mark), dir, cap)
        IO.print_err("episteme: packed log batches " ++ U32.show(U32.inc(mark))
          ++ " to " ++ U32.show(top) ++ " into the " ++ U32.show(cap) ++ "-character shards")

# catch the shards of one size up with the log: each source's shards go on
# from its tail with its records of every log batch above the mark, one
# batch at a time
def Ingest.sync(+cap: U32) -> IO(Unit):
  do IO<Unit>:
    +top : U32 <- St.Store.top()
    +mark : U32 <- St.Store.mark(cap)
    Ingest.sync.if(U32.is_lt(mark, top), cap, mark, top)

# catch the shards of the configured size up with the log
def Ingest.caught() -> IO(Unit):
  do IO<Unit>:
    cfg : St.Config <- St.Store.config()
    +cap : U32 <- St.Store.cap(cfg)
    Ingest.sync(cap)

# append the records as one batch with the connector's cursor, pack them
# after their sources' tails and write the shards; none appends and
# writes nothing
def Ingest.write(
  +fresh: List<&2, R.Record>,
  +cap: U32,
  +conn: String,
  cursor: String
) -> IO(U32):
  match fresh:
    case Nil{}:
      IO.pure(U32, 0)
    case Con{_rec, _rest}:
      do IO<U32>:
        +k : U32 <- St.Store.append(conn, cursor, fresh)
        Ingest.pack(cap, [St.Numbered{k, fresh}], k)
        St.Store.cache(conn, k)
        return U32.from_nat(List.length(&2, R.Record, fresh))

# ingest a connector's records: the shards catch up with the log, then
# the records that fit are appended as one batch whose header holds the
# connector's cursor, and packed after their sources' tails. Answers how
# many
def Ingest.run(+conn: String, +recs: List<&2, R.Record>, cursor: String) -> IO(U32):
  do IO<U32>:
    cfg : St.Config <- St.Store.config()
    +cap : U32 <- St.Store.cap(cfg)
    Ingest.sync(cap)
    Ingest.skipped(recs)
    Ingest.write(R.Record.fitting(recs), cap, conn, cursor)

# pack the whole log again, from shard 1 of each source, into the shards
# of the configured size; other sizes are left alone. The mark goes first,
# so a reshard stopped half way packs again from batch 1. Answers how
# many shards
def Ingest.reshard() -> IO(U32):
  do IO<U32>:
    cfg : St.Config <- St.Store.config()
    +cap : U32 <- St.Store.cap(cfg)
    +dir : String <- St.Store.dir(cap)
    St.Store.remove(dir ++ "/covered.json")
    St.Store.remove(dir)
    Ingest.sync(cap)
    St.Store.count(cap)
