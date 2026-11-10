# episteme/src/store: the data under EPISTEME_HOME. The log is
# log/<batch>.jsonl, batches numbered from 1 and never changed, each a
# header line {"conn", "cursor"} (the connector that wrote it and its
# cursor after it) and then one record per line; the shards of one size
# are split by source: shards/<chars>/<Shard.dir(source)>/<n>.json when
# frozen and .../tail.json, {"covered", "shard"}, for the tail and the
# last batch packed into it, beside .../sizes, the frozen shards' sizes, and shards/<chars>/covered.json, {"covered"},
# the last batch every source of that size is caught up with;
# state/<conn>.json caches the batch holding a connector's latest
# cursor; config.json holds the settings. Numbers in file
# names are zero-padded to 8 digits, so name order is number order. IO:
# the trusted shell, which only runs what the pure core decides.
#
# Trusted, not proved: `src/store.bend` keeps the data under `Store.home()`,
# `$EPISTEME_HOME` or `$HOME/.local/share/episteme`, with numbers in file names
# zero-padded to 8 digits and directories made with `mkdir -p`. `Store.config`
# reads `config.json`, first writing `{"shard_tokens": 16384,
# "chars_per_token": 255, "pool": [["http://127.0.0.1:18111", 4]],
# "budget_tokens": 60000}` when it is missing, and stops, naming the field,
# when one is missing or of the wrong kind (`pool` must be an array of `[url,
# slots]`). `Store.cap` is `shard_tokens * chars_per_token / 100` characters
# and stops with a message when the product overflows 32 bits or the size is
# under `2 * Para.max()`. `Store.append(conn, c, xs)` writes the batch
# numbered one above the highest in `log/` as one file with ezsys's
# `file.save` (written whole or not at all): a header line `{"conn": conn,
# "cursor": c}`, then one `Record.to_line` per record; it stops rather than
# overwrite a batch that exists. `Store.log` reads every batch in name order
# and stops at a file that is no batch. `Store.cursor(conn)` is the cursor in
# the latest batch `conn` wrote, `""` when there is none, read from each
# batch's header line alone (the file's first line feed within its first MiB,
# else its whole text), never its records: `state/<conn>.json`, `{"batch":
# k}`, is only a cache of where to start reading, and when the batches from
# `k` on hold none of `conn`'s, every batch's header is read. The shards of
# one size are split by source (laws/ShardHoldsOneSource.bend) under
# `shards/<chars>/<Shard.dir(s)>/` (laws/SourceDirsAreSafeAndDistinct.bend).
# `Store.put_shards(chars, s, ss, k)` writes source `s`'s shards in the order
# given, each frozen one to `<n>.json` in its directory, and last the tail to
# `tail.json` there as `{"covered": k, "shard": ...}`, `k` the last log batch
# holding one of the source's records packed; `Store.tail(chars, s)` reads it,
# or answers None when the source has no directory, and stops, telling the
# user to run `episteme ingest --reshard`, when the directory holds files but
# no `tail.json`; `Store.shards` stops the same way on such a directory.
# After a source's shards `Store.put_shards` writes `sizes` in its
# directory: a JSON array of `[chars, paras, last]`, one for each frozen
# shard in number order, `last` the latest `ts` among its records (a frozen
# shard never changes, laws/FreezingIsStable.bend, so neither do these). It appends the sizes of the frozen shards just
# written when the file held one for every frozen shard before them, and
# else reads the directory's frozen shards and writes all of theirs, so a
# directory written before there was a sizes file gets one at its next
# ingest. `Store.light(chars, f)` answers `Store.shards(chars, f)` as
# lights: for a directory with a tail whose `sizes` holds as many sizes as
# the directory has frozen shard files, each frozen shard is left unread
# (its number from its file name, its source from the directory name, its
# code points, paragraph count and latest record ts from `sizes`, no items,
# and its path) and
# only the tail is read; any other directory is read whole. A missing,
# unreadable or short `sizes` only costs the reading.
# `shards/<chars>/covered.json`, `{"covered": k}`, is the mark: every source
# is caught up with the log up to batch `k`; `Store.mark` reads it, 0 when it
# is missing. `Store.shards(chars, f)` reads, in name order, the directories
# under `shards/<chars>/` whose name `Filter.reads(f, ...)` takes
# (laws/FilterHitsChosenSources.bend: `Shard.undir` reads it as a source
# `Filter.picks` takes; the empty prefix takes every source), each one's
# `.json` files in name order, so a source's frozen shards ascend by number
# and its tail comes last; any other name is skipped.
#
# Why it is trusted: It is IO sequencing over ezsys's `file.read`, `file.save`
# and `dir.list` and Base's `Process.run` (`mkdir -p`, `rm -rf`), which no law
# reaches; ezsys's own gate trusts the same effects (on its src/sys.bend).
# `tests/smoke.sh` runs it end to end.
import Base
import ./record.bend as R
import ./shard.bend as S
import ./para.bend as P
import ./filter.bend as F
import ./excerpt.bend as E
import ezsys@0.1.0.0/main.bend as Sys
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# a reader instance: its URL and its slot count
type Slot is Data:
  Slot{url: String, slots: U32}

# the settings: the shard size in reader tokens, characters per token
# times 100 (255 is 2.55), the reader pool and the excerpt budget in
# tokens
type Config is Data:
  Config{shard_tokens: U32, chars_per_token: U32, pool: List<&2, Slot>,
    budget_tokens: U32}

# the data directory: $EPISTEME_HOME, or $HOME/.local/share/episteme
def Store.home() -> IO(String):
  do IO<String>:
    home : String <- Sys.env.or("HOME", "")
    Sys.env.or("EPISTEME_HOME", home ++ "/.local/share/episteme")

# True for the arguments of an ingest run, which takes the lock first
def Store.ingesting(xs: List<&1, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{_prog, rest}:
      match rest:
        case Nil{}:
          False{}
        case Con{cmd, _more}:
          String.eq(cmd, "ingest")

# remove the lock; a failure to is ignored, as the run is ending
def Store.unlock() -> IO(Unit):
  do IO<Unit>:
    home : String <- Store.home()
    +path : String = home ++ "/lock"
    _res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("rmdir", ["--", path], "", 65536, 60000)
    return Unit{}

# remove the lock when this run holds it
def Store.release.if(held: Bool) -> IO(Unit):
  match held:
    case True{}:
      Store.unlock()
    case False{}:
      IO.pure(Unit, Unit{})

# remove the lock when this run is an ingest: an ingest holds it from its
# first step, so no other run removes it
def Store.release() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    Store.release.if(Store.ingesting(xs))

# exit with code, first removing the lock when this run holds it
def Store.exit(code: U32) -> IO(Unit):
  do IO<Unit>:
    Store.release()
    IO.exit(code)

# stop with a message on stderr, first removing the lock when this run
# holds it
def Store.die(-A: Type, msg: String) -> IO(A):
  do IO<A>:
    Store.release()
    IO.die(A, 1, "episteme: " ++ msg)

# nothing when ok, else stop with msg
def Store.exited(ok: Bool, msg: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Store.die(Unit, msg)

# a command's result: nothing when it ran and exited 0, else stop
def Store.ran(
  res: Result<&1, &1, U32 & String, U32 & (String & String)>,
  what: String
) -> IO(Unit):
  match res:
    case Fail{(_code, why)}:
      Store.die(Unit, what ++ ": " ++ why)
    case Done{(code, (_out, err))}:
      Store.exited(U32.is_eq(code, 0), what ++ ": " ++ err)

# make a directory and its parents
def Store.mkdir(+path: String) -> IO(Unit):
  do IO<Unit>:
    res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("mkdir", ["-p", path], "", 65536, 60000)
    Store.ran(res, "mkdir -p " ++ path)

# a save's result: nothing when it worked, else stop
def Store.saved(res: Result<&1, &1, U32 & String, Unit>, +path: String) -> IO(Unit):
  match res:
    case Fail{(code, why)}:
      Store.die(Unit, Sys.err.os(code, why, path))
    case Done{_u}:
      IO.pure(Unit, Unit{})

# save a file atomically, or stop
def Store.save(+path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    res : Result<&1, &1, U32 & String, Unit> <- Sys.file.save(path, text)
    Store.saved(res, path)

# nothing when ok, else refuse with exit 1 naming the lock, leaving it in
# place for its holder
def Store.taken(ok: Bool, path: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        IO.print_err("episteme: " ++ path ++ " exists: another ingest is running; if none is, remove it by hand")
        IO.exit(1)

# nothing when the lock was taken, else refuse with exit 1 naming the lock,
# leaving it in place
def Store.locked(
  res: Result<&1, &1, U32 & String, U32 & (String & String)>,
  +path: String
) -> IO(Unit):
  match res:
    case Fail{_err}:
      Store.taken(False{}, path)
    case Done{(code, _out)}:
      Store.taken(U32.is_eq(code, 0), path)

# take the lock an ingest holds while it writes the log and the shards:
# <home>/lock, made with mkdir without -p, so it fails when the lock exists
def Store.lock() -> IO(Unit):
  do IO<Unit>:
    +home : String <- Store.home()
    Store.mkdir(home)
    +path : String = home ++ "/lock"
    res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("mkdir", ["--", path], "", 65536, 60000)
    Store.locked(res, path)

# a field's value, or stop naming the field
def Store.need(-A: Data, got: Maybe<&2, A>, field: String) -> IO(A):
  match got:
    case None{}:
      Store.die(A, "config.json: \"" ++ field ++ "\" is missing or of the wrong kind")
    case Some{val}:
      IO.pure(A, val)

# a pool entry [url, slots], or None when it is not one
def Store.slot.of(two: Bool, url: Maybe<&2, String>, slots: Maybe<&2, U32>) -> Maybe<&2, Slot>:
  match two url slots:
    case True{} Some{u} Some{n}:
      Some{Slot{u, n}}
    case _ _ _:
      None{}

# a pool entry read from [url, slots], or None
def Store.slot(+js: Value.Json) -> Maybe<&2, Slot>:
  Store.slot.of(Bool.and(Json.is_arr(js), U32.is_eq(Json.len(js), 2)),
    Json.as_str(Json.at(js, 0)), Json.as_u32(Json.at(js, 1)))

# a slot ahead of more, or None when either is missing
def Store.slot.cons(got: Maybe<&2, Slot>, more: Maybe<&2, List<&2, Slot>>) -> Maybe<&2, List<&2, Slot>>:
  match got more:
    case Some{x} Some{xs}:
      Some{x <> xs}
    case _ _:
      None{}

# pool entries, in order, or None when one is not an entry
def Store.slots(js: List<&2, Value.Json>) -> Maybe<&2, List<&2, Slot>>:
  match js:
    case Nil{}:
      Some{[]}
    case Con{head, rest}:
      Store.slot.cons(Store.slot(head), Store.slots(rest))

# the pool read from its JSON array, or None when it is not one
def Store.pool.if(arr: Bool, js: Value.Json) -> Maybe<&2, List<&2, Slot>>:
  match arr:
    case True{}:
      Store.slots(Json.items(js))
    case False{}:
      None{}

# the pool, or None when it is not an array of entries
def Store.pool(+js: Value.Json) -> Maybe<&2, List<&2, Slot>>:
  Store.pool.if(Json.is_arr(js), js)

# the settings read from a parsed config.json, or stop naming the first
# field that is missing or of the wrong kind
def Store.config.of(+js: Value.Json) -> IO(Config):
  do IO<Config>:
    tokens : U32 <- Store.need(U32, Json.as_u32(Json.get(js, "shard_tokens")), "shard_tokens")
    per : U32 <- Store.need(U32, Json.as_u32(Json.get(js, "chars_per_token")), "chars_per_token")
    pool : List<&2, Slot> <- Store.need(List<&2, Slot>, Store.pool(Json.get(js, "pool")), "pool")
    budget : U32 <- Store.need(U32, Json.as_u32(Json.get(js, "budget_tokens")), "budget_tokens")
    return Config{tokens, per, pool, budget}

# the settings from config.json's text, or stop
def Store.config.parsed(got: Maybe<&2, Value.Json>) -> IO(Config):
  match got:
    case None{}:
      Store.die(Config, "config.json is not JSON")
    case Some{js}:
      Store.config.of(js)

# the config.json written on the first run
def Store.config.default() -> String:
  "{\"shard_tokens\": 16384, \"chars_per_token\": 255, \"pool\": [[\"http://127.0.0.1:18111\", 4]], \"budget_tokens\": 60000}\n"

# the settings from a read of config.json; a missing one is written with
# the defaults first
def Store.config.read(
  res: Result<&1, &1, U32 & String, String>,
  +home: String
) -> IO(Config):
  match res:
    case Done{text}:
      Store.config.parsed(Json.parse(text))
    case Fail{_err}:
      do IO<Config>:
        Store.mkdir(home)
        Store.save(home ++ "/config.json", Store.config.default())
        Store.config.parsed(Json.parse(Store.config.default()))

# the settings in config.json, written with the defaults on the first run
def Store.config() -> IO(Config):
  do IO<Config>:
    +home : String <- Store.home()
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(home ++ "/config.json")
    Store.config.read(res, home)

# a path under the data directory
def Store.path(rel: String) -> IO(String):
  do IO<String>:
    home : String <- Store.home()
    return home ++ "/" ++ rel

# a number zero-padded to 8 digits
def Store.pad(num: U32) -> String:
  +digits = U32.show(num)
  String.repeat("0", Nat.sub(8n, String.length(digits))) ++ digits

# the shard size when it is big enough and did not overflow, else stop
def Store.cap.if(fits: Bool, big: Bool, +cap: U32) -> IO(U32):
  match fits big:
    case False{} _:
      Store.die(U32, "shard_tokens * chars_per_token overflows 32 bits")
    case True{} True{}:
      IO.pure(U32, cap)
    case True{} False{}:
      Store.die(U32, "the shard size " ++ U32.show(cap)
        ++ " is under 2 * PARA_MAX; raise shard_tokens or chars_per_token")

# True when tokens * per does not overflow 32 bits
def Store.cap.fits(+tokens: U32, +per: U32) -> Bool:
  Bool.or(U32.is_eq(tokens, 0), U32.is_eq(U32.div(U32.mul(tokens, per), tokens), per))

# the shard size in characters, shard_tokens * chars_per_token / 100, or
# stop when that overflows or is under 2 * PARA_MAX
def Store.cap(cfg: Config) -> IO(U32):
  match cfg:
    case Config{+tokens, +per, _pool, _budget}:
      +cap = U32.div(U32.mul(tokens, per), 100)
      Store.cap.if(Store.cap.fits(tokens, per),
        U32.is_ge(cap, U32.mul(2, P.Para.max())), cap)

# a directory's names, or none when it cannot be read
def Store.names(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    res : Result<&1, &1, U32 & String, List<&2, String>> <- Sys.dir.list(path)
    return Result.default(&1, &1, U32 & String, List<&2, String>, res, [])

# records as JSON lines, each ending in a line feed
def Store.lines(recs: List<&2, R.Record>) -> String:
  match recs:
    case Nil{}:
      ""
    case Con{rec, rest}:
      R.Record.to_line(rec) ++ "\n" ++ Store.lines(rest)

# the number before ".jsonl", or 0
def Store.num.if(batch: Bool, +name: String) -> U32:
  match batch:
    case True{}:
      Maybe.default(&2, U32,
        U32.read(String.take(name, Nat.sub(String.length(name), 6n))), 0)
    case False{}:
      0

# the number of a log batch's file name, or 0 when it is none
def Store.num(+name: String) -> U32:
  Store.num.if(String.ends_with(name, ".jsonl"), name)

# name ahead of rest when keep
def Store.after.if(keep: Bool, name: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      name <> rest
    case False{}:
      rest

# the names of log batches numbered above num, in name order
def Store.after(names: List<&2, String>, +num: U32) -> List<&2, String>:
  match names:
    case Nil{}:
      []
    case Con{+name, rest}:
      Store.after.if(U32.is_gt(Store.num(name), num), name, Store.after(rest, num))

# the highest batch number of names, or top
def Store.top.go(names: List<&2, String>, +top: U32) -> U32:
  match names:
    case Nil{}:
      top
    case Con{+name, rest}:
      Store.top.go(rest, U32.max(top, Store.num(name)))

# the highest log batch number, 0 for an empty log
def Store.top() -> IO(U32):
  do IO<U32>:
    +dir : String <- Store.path("log")
    names : List<&2, String> <- Store.names(dir)
    return Store.top.go(names, 0)

# stop when a file exists, else nothing
def Store.fresh(res: Result<&1, &1, U32 & String, String>, +path: String) -> IO(Unit):
  match res:
    case Fail{_err}:
      IO.pure(Unit, Unit{})
    case Done{_text}:
      Store.die(Unit, "refusing to overwrite " ++ path)

# a batch's header line: its connector and that connector's cursor
def Store.header(conn: String, cursor: String) -> String:
  Json.print(Json.obj([("conn", Json.str(conn)), ("cursor", Json.str(cursor))])) ++ "\n"

# append records to the log as one new batch, numbered one above the
# highest, with conn's cursor after them in its header; answers its
# number. It never overwrites a batch
def Store.append(conn: String, cursor: String, +recs: List<&2, R.Record>) -> IO(U32):
  do IO<U32>:
    +dir : String <- Store.path("log")
    Store.mkdir(dir)
    +top : U32 <- Store.top()
    +path : String = dir ++ "/" ++ Store.pad(U32.inc(top)) ++ ".jsonl"
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(path)
    Store.fresh(res, path)
    Store.save(path, Store.header(conn, cursor) ++ Store.lines(recs))
    return U32.inc(top)

# a read's text, or stop
def Store.text(res: Result<&1, &1, U32 & String, String>, +path: String) -> IO(String):
  match res:
    case Fail{(code, why)}:
      Store.die(String, Sys.err.os(code, why, path))
    case Done{text}:
      IO.pure(String, text)

# a file's text, or stop
def Store.read(+path: String) -> IO(String):
  do IO<String>:
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(path)
    Store.text(res, path)

# a record ahead of more, or None when either is missing
def Store.cons(
  got: Maybe<&2, R.Record>,
  more: Maybe<&2, List<&2, R.Record>>
) -> Maybe<&2, List<&2, R.Record>>:
  match got more:
    case Some{rec} Some{recs}:
      Some{rec <> recs}
    case _ _:
      None{}

# the records of a batch's lines, an empty line skipped, or None when a
# line is no record
def Store.parsed(lines: List<&2, String>) -> Maybe<&2, List<&2, R.Record>>:
  match lines:
    case Nil{}:
      Some{[]}
    case Con{SNil{}, rest}:
      Store.parsed(rest)
    case Con{SCon{head, tail}, rest}:
      Store.cons(R.Record.of_line(SCon{head, tail}), Store.parsed(rest))

# a log batch: the connector that wrote it, its cursor, its records
type Batch is Data:
  Batch{conn: String, cursor: String, recs: List<&2, R.Record>}

# a batch of its header fields, or None when one is missing
def Store.batch.fields(
  conn: Maybe<&2, String>,
  cursor: Maybe<&2, String>,
  recs: List<&2, R.Record>
) -> Maybe<&2, Batch>:
  match conn cursor:
    case Some{cn} Some{cr}:
      Some{Batch{cn, cr, recs}}
    case _ _:
      None{}

# a batch of a parsed header and the records of its other lines, or None
def Store.batch.of(head: Maybe<&2, Value.Json>, recs: Maybe<&2, List<&2, R.Record>>) -> Maybe<&2, Batch>:
  match head recs:
    case Some{+js} Some{rs}:
      Store.batch.fields(Json.as_str(Json.get(js, "conn")), Json.as_str(Json.get(js, "cursor")), rs)
    case _ _:
      None{}

# a batch read from its lines, or None when it is not one
def Store.batch.lines(lines: List<&2, String>) -> Maybe<&2, Batch>:
  match lines:
    case Nil{}:
      None{}
    case Con{head, rest}:
      Store.batch.of(Json.parse(head), Store.parsed(rest))

# a batch, or stop when its file is not one
def Store.batch.read(got: Maybe<&2, Batch>, +file: String) -> IO(Batch):
  match got:
    case None{}:
      Store.die(Batch, file ++ " is no log batch")
    case Some{b}:
      IO.pure(Batch, b)

# a batch's records
def Store.batch.recs(batch: Batch) -> List<&2, R.Record>:
  match batch:
    case Batch{_conn, _cursor, recs}:
      recs

# the batch in a file of the log
def Store.batch.file(+file: String) -> IO(Batch):
  do IO<Batch>:
    text : String <- Store.read(file)
    Store.batch.read(Store.batch.lines(String.lines(text)), file)

# the bytes a header read takes: far more than a batch's header line, which
# holds only its connector's cursor
def Store.head.max() -> U32:
  1048576

# a batch from the first line of text, a read of its file's first bytes,
# or, when that holds no line feed, from the whole file
def Store.head.of(+text: String, at: Maybe<&2, U32>, +file: String) -> IO(Batch):
  match at:
    case Some{i}:
      Store.batch.read(Store.batch.lines([Sys.text.truncate(text, U32.to_nat(i))]), file)
    case None{}:
      Store.batch.file(file)

# a read of a file's first bytes, the file closed
def Store.head.read(pair: File & Result<&1, &1, U32 & String, String>, +file: String) -> IO(Batch):
  match pair:
    case (handle, res):
      do IO<Batch>:
        File.close(handle)
        +text : String <- Store.text(res, file)
        Store.head.of(text, Sys.text.find(text, "\n"), file)

# a batch's header from an open of its file, or stop
def Store.head.open(res: Result<&1, &1, U32 & String, File>, +file: String) -> IO(Batch):
  match res:
    case Fail{(code, why)}:
      Store.die(Batch, Sys.err.os(code, why, file))
    case Done{handle}:
      do IO<Batch>:
        pair : File & Result<&1, &1, U32 & String, String> <- File.read(handle, Store.head.max())
        Store.head.read(pair, file)

# a log batch's header alone: its connector and cursor, with no records,
# read from the file's first line without reading or parsing the records
def Store.batch.head(+file: String) -> IO(Batch):
  do IO<Batch>:
    res : Result<&1, &1, U32 & String, File> <- File.open(file, "r")
    Store.head.open(res, file)

# a log batch's number and records
type Numbered is Data:
  Numbered{num: U32, recs: List<&2, R.Record>}

# the records of the batches, in order
def Store.log.go(names: List<&2, String>, +dir: String) -> IO(List<&2, R.Record>):
  match names:
    case Nil{}:
      IO.pure(List<&2, R.Record>, [])
    case Con{name, rest}:
      do IO<List<&2, R.Record>>:
        b : Batch <- Store.batch.file(dir ++ "/" ++ name)
        more : List<&2, R.Record> <- Store.log.go(rest, dir)
        return List.append(&2, R.Record, Store.batch.recs(b), more)

# the records of the log batches numbered above num, in log order
def Store.log.after(+num: U32) -> IO(List<&2, R.Record>):
  do IO<List<&2, R.Record>>:
    +dir : String <- Store.path("log")
    names : List<&2, String> <- Store.names(dir)
    Store.log.go(Store.after(names, num), dir)

# every record of the log, in log order
def Store.log() -> IO(List<&2, R.Record>):
  Store.log.after(0)

# the directory of the shards of one size
def Store.dir(chars: U32) -> IO(String):
  Store.path("shards/" ++ U32.show(chars))

# the directory of one source's shards of one size
def Store.src(chars: U32, src: String) -> IO(String):
  do IO<String>:
    dir : String <- Store.dir(chars)
    return dir ++ "/" ++ S.Shard.dir(src)

# the "covered" of a parsed covered.json, or 0
def Store.mark.json(got: Maybe<&2, Value.Json>) -> U32:
  match got:
    case None{}:
      0
    case Some{js}:
      Maybe.default(&2, U32, Json.as_u32(Json.get(js, "covered")), 0)

# the batch a read of covered.json names, or 0 when there is none
def Store.mark.of(res: Result<&1, &1, U32 & String, String>) -> U32:
  match res:
    case Fail{_err}:
      0
    case Done{text}:
      Store.mark.json(Json.parse(text))

# the last log batch every source of one size is caught up with, 0 when
# covered.json is missing
def Store.mark(chars: U32) -> IO(U32):
  do IO<U32>:
    +dir : String <- Store.dir(chars)
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(dir ++ "/covered.json")
    return Store.mark.of(res)

# none when the mark is at the top batch, else the refusal telling the user
# to run ingest
def Store.behind.if(behind: Bool, +chars: U32, mark: U32, top: U32) -> Maybe<&2, String>:
  match behind:
    case False{}:
      None{}
    case True{}:
      Some{"the " ++ U32.show(chars) ++ "-character shards hold log batches up to "
        ++ U32.show(mark) ++ " of " ++ U32.show(top) ++ "; run episteme ingest"}

# the refusal telling the user to run episteme ingest when the shards of one
# size are behind the log: the mark is below the top batch (a size with no
# directory has mark 0); none when they are not. Reads never write the shards
def Store.behind(+chars: U32) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    +top : U32 <- Store.top()
    +mark : U32 <- Store.mark(chars)
    return Store.behind.if(U32.is_lt(mark, top), chars, mark, top)

# nothing when there is no refusal, else stop with it
def Store.ready.if(got: Maybe<&2, String>) -> IO(Unit):
  match got:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{why}:
      Store.die(Unit, why)

# stop, telling the user to run episteme ingest, when the shards of one
# size are behind the log (Store.behind)
def Store.ready(+chars: U32) -> IO(Unit):
  do IO<Unit>:
    got : Maybe<&2, String> <- Store.behind(chars)
    Store.ready.if(got)

# record that every source of one size is caught up with log batch num
def Store.mark.put(chars: U32, num: U32) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Store.dir(chars)
    Store.mkdir(dir)
    Store.save(dir ++ "/covered.json",
      Json.print(Json.obj([("covered", Json.num(U32.show(num)))])) ++ "\n")

# a parsed shard, or stop
def Store.shard.of(got: Maybe<&2, S.Shard>, +path: String) -> IO(S.Shard):
  match got:
    case None{}:
      Store.die(S.Shard, path ++ " is no shard")
    case Some{sh}:
      IO.pure(S.Shard, sh)

# a shard read from its file, or stop
def Store.shard(+path: String) -> IO(S.Shard):
  do IO<S.Shard>:
    text : String <- Store.read(path)
    Store.shard.of(S.Shard.of_json(text), path)

# a tail and the last log batch packed into its shard size
type Tail is Data:
  Tail{shard: S.Shard, covered: U32}

# a tail of its parsed parts, or None
def Store.tail.of(shard: Maybe<&2, S.Shard>, covered: Maybe<&2, U32>) -> Maybe<&2, Tail>:
  match shard covered:
    case Some{sh} Some{c}:
      Some{Tail{sh, c}}
    case _ _:
      None{}

# a tail read from tail.json's parsed text, or None
def Store.tail.json(got: Maybe<&2, Value.Json>) -> Maybe<&2, Tail>:
  match got:
    case None{}:
      None{}
    case Some{+js}:
      Store.tail.of(S.Shard.of_value(Json.get(js, "shard")), Json.as_u32(Json.get(js, "covered")))

# a tail, or stop when tail.json is not one
def Store.tail.need(got: Maybe<&2, Tail>, +path: String) -> IO(Tail):
  match got:
    case None{}:
      Store.die(Tail, path ++ " is no tail")
    case Some{t}:
      IO.pure(Tail, t)

# stop when a source directory holds files but no tail.json: its tail is
# lost, and packing on from an empty one would drop records and write over
# frozen shard 1
def Store.lost(empty: Bool, dir: String) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Store.die(Unit, dir ++ " has no tail.json; run episteme ingest --reshard")

# the tail from a read of tail.json, or None when there is none or its
# directory does not exist; stop when the directory holds other files
def Store.tail.read(res: Result<&1, &1, U32 & String, String>, +path: String, +dir: String) -> IO(Maybe<&2, Tail>):
  match res:
    case Fail{_err}:
      do IO<Maybe<&2, Tail>>:
        names : List<&2, String> <- Store.names(dir)
        Store.lost(List.is_empty(&2, String, names), dir)
        return None{}
    case Done{text}:
      do IO<Maybe<&2, Tail>>:
        t : Tail <- Store.tail.need(Store.tail.json(Json.parse(text)), path)
        return Some{t}

# the tail of one source's shards of one size and the last batch packed
# into it, or None
def Store.tail(chars: U32, src: String) -> IO(Maybe<&2, Tail>):
  do IO<Maybe<&2, Tail>>:
    +dir : String <- Store.src(chars, src)
    +path : String = dir ++ "/tail.json"
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(path)
    Store.tail.read(res, path, dir)

# a shard's file text by whether it is frozen
def Store.content.if(frozen: Bool, sh: S.Shard, covered: U32) -> String:
  match frozen:
    case True{}:
      S.Shard.to_json(sh) ++ "\n"
    case False{}:
      Json.print(Json.obj([("covered", Json.num(U32.show(covered))),
        ("shard", S.Shard.to_value(sh))])) ++ "\n"

# a shard's file text: a frozen shard's JSON, or for the tail the JSON
# {"covered", "shard"}
def Store.content(+sh: S.Shard, +covered: U32) -> String:
  match sh:
    case S.Shard{_n, _items, _sources, _chars, frozen}:
      Store.content.if(frozen, sh, covered)

# the file a shard is stored in: <n>.json when frozen, tail.json otherwise
def Store.file(sh: S.Shard) -> String:
  match sh:
    case S.Shard{n, _items, _sources, _chars, frozen}:
      match frozen:
        case True{}:
          Store.pad(n) ++ ".json"
        case False{}:
          "tail.json"

# write shards in order into dir
def Store.put.go(ss: List<&2, S.Shard>, +dir: String, +covered: U32) -> IO(Unit):
  match ss:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+sh, rest}:
      do IO<Unit>:
        Store.save(dir ++ "/" ++ Store.file(sh), Store.content(sh, covered))
        Store.put.go(rest, dir, covered)

# a frozen shard's size: its code points, its paragraphs, and the latest
# ts among its records ("" when it holds none)
type Sz is Data:
  Sz{chars: U32, paras: U32, last: String}

# the later of two ts: string order is time order
def Store.later(+one: String, +two: String) -> String:
  Bool.pick(String, String.is_ge(one, two), one, two)

# the latest ts among the records of items, at least floor
def Store.last(its: List<&2, S.Item>, +floor: String) -> String:
  match its:
    case Nil{}:
      floor
    case Con{it, rest}:
      match it:
        case S.Item{rec, _from, _upto}:
          Store.last(rest, Store.later(E.Excerpt.ts(rec), floor))

# how many paragraphs a shard holds: one label each
def Store.paras(sh: S.Shard) -> Nat:
  List.length(&2, S.Shard.Label(), S.Shard.labels(sh))

# sz ahead of rest when keep
def Store.sizes.if(keep: Bool, sz: Sz, rest: List<&2, Sz>) -> List<&2, Sz>:
  match keep:
    case True{}:
      sz <> rest
    case False{}:
      rest

# the sizes of the frozen shards of ss, in order
def Store.sizes.of(ss: List<&2, S.Shard>) -> List<&2, Sz>:
  match ss:
    case Nil{}:
      []
    case Con{+sh, rest}:
      match sh:
        case S.Shard{_n, items, _sources, chars, frozen}:
          Store.sizes.if(frozen, Sz{chars, U32.from_nat(Store.paras(sh)), Store.last(items, "")},
            Store.sizes.of(rest))

# sizes as JSON values, each [chars, paras, last]
def Store.sizes.json(szs: List<&2, Sz>) -> List<&2, Value.Json>:
  match szs:
    case Nil{}:
      []
    case Con{sz, rest}:
      match sz:
        case Sz{chars, paras, last}:
          Json.arr([Json.num(U32.show(chars)), Json.num(U32.show(paras)), Json.str(last)])
            <> Store.sizes.json(rest)

# a size of its three values, or None when one is missing
def Store.sz.all(chars: Maybe<&2, U32>, paras: Maybe<&2, U32>, last: Maybe<&2, String>) -> Maybe<&2, Sz>:
  match chars paras last:
    case Some{c} Some{p} Some{t}:
      Some{Sz{c, p, t}}
    case _ _ _:
      None{}

# a size of the values after its second, or None
def Store.sz.third(first: Value.Json, second: Value.Json, rest: List<&2, Value.Json>) -> Maybe<&2, Sz>:
  match rest:
    case Nil{}:
      None{}
    case Con{third, _more}:
      Store.sz.all(Json.as_u32(first), Json.as_u32(second), Json.as_str(third))

# a size of the values after its first, or None
def Store.sz.rest(first: Value.Json, rest: List<&2, Value.Json>) -> Maybe<&2, Sz>:
  match rest:
    case Nil{}:
      None{}
    case Con{second, more}:
      Store.sz.third(first, second, more)

# a size of the items of [chars, paras, last], or None
def Store.sz.of(got: Maybe<&2, List<&2, Value.Json>>) -> Maybe<&2, Sz>:
  match got:
    case None{}:
      None{}
    case Some{js}:
      match js:
        case Nil{}:
          None{}
        case Con{first, rest}:
          Store.sz.rest(first, rest)

# sz ahead of rest when there is one
def Store.sz.some(got: Maybe<&2, Sz>, rest: List<&2, Sz>) -> List<&2, Sz>:
  match got:
    case None{}:
      rest
    case Some{sz}:
      sz <> rest

# the sizes among JSON values, in order; a value that is no size is left out
def Store.szs.of(js: List<&2, Value.Json>) -> List<&2, Sz>:
  match js:
    case Nil{}:
      []
    case Con{+item, rest}:
      Store.sz.some(Store.sz.of(S.Shard.arr(item)), Store.szs.of(rest))

# the sizes of a parsed sizes file, none when it is no array
def Store.szs.json(got: Maybe<&2, Value.Json>) -> List<&2, Sz>:
  match got:
    case None{}:
      []
    case Some{+js}:
      Store.szs.of(Maybe.default(&2, List<&2, Value.Json>, S.Shard.arr(js), []))

# a source directory's sizes file: the sizes of its frozen shards, in
# order; none when the file is missing or is no array
def Store.sizes(+dir: String) -> IO(List<&2, Sz>):
  do IO<List<&2, Sz>>:
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(dir ++ "/sizes")
    return Store.szs.json(Json.parse(Result.default(&1, &1, U32 & String, String, res, "")))

# the number of the first shard of ss, 0 when there is none
def Store.first(ss: List<&2, S.Shard>) -> U32:
  match ss:
    case Nil{}:
      0
    case Con{sh, _rest}:
      match sh:
        case S.Shard{n, _items, _sources, _chars, _frozen}:
          n

# a tail's shard
def Store.tail.shard(tail: Tail) -> S.Shard:
  match tail:
    case Tail{sh, _covered}:
      sh

# the shard in a file: tail.json holds the tail beside its covered batch
def Store.shard.named(tail: Bool, +path: String) -> IO(S.Shard):
  match tail:
    case False{}:
      Store.shard(path)
    case True{}:
      do IO<S.Shard>:
        text : String <- Store.read(path)
        t : Tail <- Store.tail.need(Store.tail.json(Json.parse(text)), path)
        return Store.tail.shard(t)

# the shards in the named files, in order
def Store.shards.go(names: List<&2, String>, +dir: String) -> IO(List<&2, S.Shard>):
  match names:
    case Nil{}:
      IO.pure(List<&2, S.Shard>, [])
    case Con{+name, rest}:
      do IO<List<&2, S.Shard>>:
        sh : S.Shard <- Store.shard.named(String.eq(name, "tail.json"), dir ++ "/" ++ name)
        more : List<&2, S.Shard> <- Store.shards.go(rest, dir)
        return sh <> more

# the shards in a source directory, frozen ones in ascending number, then
# the tail; stop when the tail is lost
def Store.shards.in(+dir: String) -> IO(List<&2, S.Shard>):
  do IO<List<&2, S.Shard>>:
    +names : List<&2, String> <- Store.names(dir)
    Store.lost(List.any(~&2, ~String, ~(name => String.eq(name, "tail.json")), names), dir)
    Store.shards.go(List.filter(~String, ~(name => String.ends_with(name, ".json")), names), dir)

# write a source directory's sizes file after its shards ss were written:
# the sizes it held and those of the frozen shards of ss when it held one
# for every frozen shard before them, else the sizes of the frozen shards
# the directory holds, read from their files
def Store.sizes.write(fits: Bool, old: List<&2, Sz>, ss: List<&2, S.Shard>, +dir: String) -> IO(Unit):
  match fits:
    case True{}:
      Store.save(dir ++ "/sizes",
        Json.print(Json.arr(Store.sizes.json(List.append(&2, Sz, old, Store.sizes.of(ss))))) ++ "\n")
    case False{}:
      do IO<Unit>:
        all : List<&2, S.Shard> <- Store.shards.in(dir)
        Store.save(dir ++ "/sizes", Json.print(Json.arr(Store.sizes.json(Store.sizes.of(all)))) ++ "\n")

# bring a source directory's sizes file up to date with the shards ss just
# written there
def Store.sizes.put(+dir: String, +ss: List<&2, S.Shard>) -> IO(Unit):
  do IO<Unit>:
    +old : List<&2, Sz> <- Store.sizes(dir)
    Store.sizes.write(U32.is_eq(U32.inc(U32.from_nat(List.length(&2, Sz, old))), Store.first(ss)),
      old, ss, dir)

# write one source's shards of one size: each frozen one as <n>.json, the
# tail as tail.json with covered, the last log batch packed, in order, so
# the tail is written last, and then the sizes file
def Store.put_shards(chars: U32, src: String, +ss: List<&2, S.Shard>, +covered: U32) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Store.src(chars, src)
    Store.mkdir(dir)
    Store.put.go(ss, dir, covered)
    Store.sizes.put(dir, ss)

# the shards in a directory when picked, else none
def Store.shards.if(picked: Bool, +dir: String) -> IO(List<&2, S.Shard>):
  match picked:
    case True{}:
      Store.shards.in(dir)
    case False{}:
      IO.pure(List<&2, S.Shard>, [])

# the shards of the named source directories whose source sels picks, in
# name order
def Store.shards.dirs(names: List<&2, String>, +sels: List<&2, F.Sel>, +dir: String) -> IO(List<&2, S.Shard>):
  match names:
    case Nil{}:
      IO.pure(List<&2, S.Shard>, [])
    case Con{+name, rest}:
      do IO<List<&2, S.Shard>>:
        ss : List<&2, S.Shard> <- Store.shards.if(F.Filter.reads(sels, name), dir ++ "/" ++ name)
        more : List<&2, S.Shard> <- Store.shards.dirs(rest, sels, dir)
        return List.append(&2, S.Shard, ss, more)

# the shards of one size of every source a selector of sels picks
# (Filter.reads; the empty prefix picks every source): source directories
# in name order, each one's frozen shards in ascending number, then its
# tail; a name Shard.undir reads as no source is skipped
def Store.shards(chars: U32, +sels: List<&2, F.Sel>) -> IO(List<&2, S.Shard>):
  do IO<List<&2, S.Shard>>:
    +dir : String <- Store.dir(chars)
    names : List<&2, String> <- Store.names(dir)
    Store.shards.dirs(names, sels, dir)

# a shard as a question first sees it. A frozen shard whose source has a
# sizes file is not read: shard holds its number, its source, its code
# points and no items, sized its paragraph count and path its file. A
# shard that was read has no count and no path. last is an unread shard's
# latest record ts
type Light is Data:
  Light{shard: S.Shard, sized: Maybe<&2, Nat>, path: String, last: String}

# shards that were read, as lights
def Store.light.loaded(ss: List<&2, S.Shard>) -> List<&2, Light>:
  match ss:
    case Nil{}:
      []
    case Con{sh, rest}:
      Light{sh, None{}, "", ""} <> Store.light.loaded(rest)

# the number of a frozen shard's file name <n>.json, or 0
def Store.shard.num(+name: String) -> U32:
  Maybe.default(&2, U32, U32.read(String.take(name, Nat.sub(String.length(name), 5n))), 0)

# the light of the frozen shard in the file name, from its size
def Store.light.one(+name: String, sz: Sz, dir: String, src: String) -> Light:
  match sz:
    case Sz{chars, paras, last}:
      Light{S.Shard{Store.shard.num(name), [], [src], chars, True{}}, Some{U32.to_nat(paras)},
        dir ++ "/" ++ name, last}

# the lights of the frozen shards in the named files, beside their sizes
def Store.light.frozen(names: List<&2, String>, szs: List<&2, Sz>, +dir: String, +src: String) -> List<&2, Light>:
  match names szs:
    case Con{name, rest} Con{sz, more}:
      Store.light.one(name, sz, dir, src) <> Store.light.frozen(rest, more, dir, src)
    case _ _:
      []

# name ahead of rest unless it is the tail's
def Store.frozen.if(tail: Bool, name: String, rest: List<&2, String>) -> List<&2, String>:
  match tail:
    case True{}:
      rest
    case False{}:
      name <> rest

# the names of files but the tail's
def Store.frozen(names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}:
      []
    case Con{+name, rest}:
      Store.frozen.if(String.eq(name, "tail.json"), name, Store.frozen(rest))

# a source directory's lights: its frozen shards unread and its tail read
# when sized, else every shard read
def Store.light.pick(
  sized: Bool,
  frozen: List<&2, String>,
  szs: List<&2, Sz>,
  files: List<&2, String>,
  +dir: String,
  src: String
) -> IO(List<&2, Light>):
  match sized:
    case True{}:
      do IO<List<&2, Light>>:
        tail : S.Shard <- Store.shard.named(True{}, dir ++ "/tail.json")
        return List.append(&2, Light, Store.light.frozen(frozen, szs, dir, src), [Light{tail, None{}, "", ""}])
    case False{}:
      do IO<List<&2, Light>>:
        ss : List<&2, S.Shard> <- Store.shards.go(files, dir)
        return Store.light.loaded(ss)

# the lights of the source src in its directory, frozen shards in ascending
# number, then the tail; stop when the tail is lost. The frozen shards are
# left unread when the directory has a tail and its sizes file holds one
# size for each of them
def Store.light.in(+dir: String, src: String) -> IO(List<&2, Light>):
  do IO<List<&2, Light>>:
    +names : List<&2, String> <- Store.names(dir)
    +tail : Bool = List.any(~&2, ~String, ~(name => String.eq(name, "tail.json")), names)
    Store.lost(tail, dir)
    +files : List<&2, String> = List.filter(~String, ~(name => String.ends_with(name, ".json")), names)
    +frozen : List<&2, String> = Store.frozen(files)
    +szs : List<&2, Sz> <- Store.sizes(dir)
    Store.light.pick(Bool.and(tail, U32.is_eq(U32.from_nat(List.length(&2, Sz, szs)),
      U32.from_nat(List.length(&2, String, frozen)))), frozen, szs, files, dir, src)

# the lights in a directory when picked, else none
def Store.light.if(picked: Bool, +dir: String, src: String) -> IO(List<&2, Light>):
  match picked:
    case True{}:
      Store.light.in(dir, src)
    case False{}:
      IO.pure(List<&2, Light>, [])

# the lights of the named source directories whose source sels picks, in
# name order
def Store.light.dirs(names: List<&2, String>, +sels: List<&2, F.Sel>, +dir: String) -> IO(List<&2, Light>):
  match names:
    case Nil{}:
      IO.pure(List<&2, Light>, [])
    case Con{+name, rest}:
      do IO<List<&2, Light>>:
        ls : List<&2, Light> <- Store.light.if(F.Filter.reads(sels, name), dir ++ "/" ++ name,
          Maybe.default(&2, String, S.Shard.undir(name), ""))
        more : List<&2, Light> <- Store.light.dirs(rest, sels, dir)
        return List.append(&2, Light, ls, more)

# Store.shards as lights: the same shards in the same order, a frozen shard
# of a source with a sizes file left unread
def Store.light(chars: U32, +sels: List<&2, F.Sel>) -> IO(List<&2, Light>):
  do IO<List<&2, Light>>:
    +dir : String <- Store.dir(chars)
    names : List<&2, String> <- Store.names(dir)
    Store.light.dirs(names, sels, dir)

# every source: the empty prefix
def Store.every() -> List<&2, F.Sel>:
  [F.Prefix{""}]

# how many shards a source directory holds when picked: its .json files
def Store.count.if(picked: Bool, +dir: String) -> IO(Nat):
  match picked:
    case True{}:
      do IO<Nat>:
        names : List<&2, String> <- Store.names(dir)
        return List.length(&2, String,
          List.filter(~String, ~(name => String.ends_with(name, ".json")), names))
    case False{}:
      IO.pure(Nat, 0n)

# how many shards the named source directories hold
def Store.count.dirs(names: List<&2, String>, +dir: String) -> IO(Nat):
  match names:
    case Nil{}:
      IO.pure(Nat, 0n)
    case Con{+name, rest}:
      do IO<Nat>:
        num : Nat <- Store.count.if(F.Filter.reads(Store.every(), name), dir ++ "/" ++ name)
        more : Nat <- Store.count.dirs(rest, dir)
        return Nat.add(num, more)

# how many shards of one size there are, counted by their files, none read:
# as many as Store.shards(chars, Store.every()) reads
def Store.count(chars: U32) -> IO(U32):
  do IO<U32>:
    +dir : String <- Store.dir(chars)
    names : List<&2, String> <- Store.names(dir)
    num : Nat <- Store.count.dirs(names, dir)
    return U32.from_nat(num)

# the "batch" of a parsed state file, or 0
def Store.cache.json(got: Maybe<&2, Value.Json>) -> U32:
  match got:
    case None{}:
      0
    case Some{js}:
      Maybe.default(&2, U32, Json.as_u32(Json.get(js, "batch")), 0)

# the batch state/<conn>.json names, or 0
def Store.cache.of(res: Result<&1, &1, U32 & String, String>) -> U32:
  match res:
    case Fail{_err}:
      0
    case Done{text}:
      Store.cache.json(Json.parse(text))

# remember that log batch num holds conn's latest cursor; only a cache,
# since the cursor itself is in the batch
def Store.cache(conn: String, num: U32) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- Store.path("state")
    Store.mkdir(dir)
    Store.save(dir ++ "/" ++ conn ++ ".json",
      Json.print(Json.obj([("batch", Json.num(U32.show(num)))])) ++ "\n")

# cursor when it is conn's, else cur
def Store.mine.if(hit: Bool, cursor: String, cur: String) -> String:
  match hit:
    case True{}:
      cursor
    case False{}:
      cur

# the cursor of a batch when conn wrote it, else cur
def Store.mine(batch: Batch, +conn: String, cur: String) -> String:
  match batch:
    case Batch{bconn, cursor, _recs}:
      Store.mine.if(String.eq(bconn, conn), cursor, cur)

# conn's latest cursor in the named batches, in order, after cur; only
# each batch's header line is read
def Store.scan(names: List<&2, String>, +dir: String, +conn: String, cur: String) -> IO(String):
  match names:
    case Nil{}:
      IO.pure(String, cur)
    case Con{name, rest}:
      do IO<String>:
        b : Batch <- Store.batch.head(dir ++ "/" ++ name)
        Store.scan(rest, dir, conn, Store.mine(b, conn, cur))

# the cursor found from the cache, or, when none was found there, the
# cursor found reading every batch (a cache that names no batch of conn)
def Store.cursor.if(none: Bool, got: String, names: List<&2, String>, +dir: String, +conn: String) -> IO(String):
  match none:
    case False{}:
      IO.pure(String, got)
    case True{}:
      Store.scan(names, dir, conn, "")

# how far a connector got: the cursor in its latest log batch, "" when it
# wrote none. The cache names a batch to start from; it and later batches
# are read for the newest; when they hold none, every batch is read
def Store.cursor(+conn: String) -> IO(String):
  do IO<String>:
    +state : String <- Store.path("state")
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(state ++ "/" ++ conn ++ ".json")
    +from : U32 = Store.cache.of(res)
    +dir : String <- Store.path("log")
    +names : List<&2, String> <- Store.names(dir)
    +got : String <- Store.scan(Store.after(names, U32.sub(from, U32.min(from, 1))), dir, conn, "")
    Store.cursor.if(Bool.and(String.is_empty(got), Bool.not(U32.is_eq(from, 0))), got, names, dir, conn)

# remove a directory and everything under it
def Store.remove(+path: String) -> IO(Unit):
  do IO<Unit>:
    res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("rm", ["-rf", path], "", 65536, 600000)
    Store.ran(res, "rm -rf " ++ path)
