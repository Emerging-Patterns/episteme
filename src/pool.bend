# episteme/src/pool: the reader pool. One worker per slot of every healthy
# instance pulls shards from one queue, so a faster instance takes more of
# them. The shards whose read failed are read once more, in a second pass
# by the workers of the other instances, and then stand. Each pass fills
# its queue and closes it, so every worker stops when it drains. IO: the
# trusted shell around Read.failed and Read.ordered.
#
# Trusted, not proved: `Pool.run(pool, ss, q)` checks each instance's health
# in order, skipping one that fails with the stderr line `skipping <url>:
# <why>`, and stops with exit 2 when none is healthy. It reads in two passes.
# A pass fills one `Chan` queue with its shards and closes it, then starts one
# worker per slot of the pass's instances (`IO.fork`, each with its own
# `id_slot`); each worker reads shards until the queue is drained (so a faster
# instance takes more), and the pass ends when it has one read per shard and
# every worker is joined. Pass 1 reads every shard with every healthy
# instance. Pass 2 takes the reads of pass 1 that `Read.failed` lists and, for
# each instance they failed on, reads those shards again with the workers of
# the other healthy instances, or with all workers when there is no other. It
# answers the pass 2 reads ahead of the pass 1 reads, so `Read.ordered` takes
# a shard's second read when there is one; a read that failed twice stands as
# failed.
#
# Why it is trusted: It is concurrency over Base's `IO.fork`, `IO.join` and
# `Chan`, which no law reaches; which reads are read again is
# laws/FailedReadsListed.bend (`Read.failed`) and one read per shard is
# laws/EveryShardIsRead.bend. Each pass's queue is closed once filled, so it
# ends by construction. `tests/live.sh` checks a dead URL beside a healthy
# reader (skipped, 0 failed) and a pool whose every call errors (every shard
# failed, exit 1); `tests/smoke.sh` checks that a pool with no healthy
# instance exits 2.
import Base
import ./shard.bend as S
import ./read.bend as Rd
import ./reader.bend as Rr
import ./store.bend as St

# a worker: its number, its instance and its slot there
type Worker is Data:
  Worker{id: U32, url: String, slot: U32}

# the workers of cnt more slots of the instance at url, from slot on,
# each numbered id + its slot
def Pool.slots(cnt: Nat, +url: String, +slot: U32, +id: U32) -> List<&2, Worker>:
  match cnt:
    case 0n:
      []
    case 1n+m:
      Worker{U32.add(id, slot), url, slot} <> Pool.slots(m, url, U32.inc(slot), id)

# the workers of the instances, one per slot, numbered from id
def Pool.workers(insts: List<&2, St.Slot>, +id: U32) -> List<&2, Worker>:
  match insts:
    case Nil{}:
      []
    case Con{inst, rest}:
      match inst:
        case St.Slot{+url, +n}:
          List.append(&2, Worker, Pool.slots(U32.to_nat(n), url, 0, id),
            Pool.workers(rest, U32.add(id, n)))

# an instance kept when healthy, else skipped with a line on stderr
def Pool.keep(got: Maybe<&2, String>, inst: St.Slot, rest: List<&2, St.Slot>) -> IO(List<&2, St.Slot>):
  match got:
    case None{}:
      IO.pure(List<&2, St.Slot>, inst <> rest)
    case Some{why}:
      match inst:
        case St.Slot{url, _n}:
          do IO<List<&2, St.Slot>>:
            IO.print_err("skipping " ++ url ++ ": " ++ why)
            return rest

# the instances whose /health answers, in order
def Pool.healthy(insts: List<&2, St.Slot>) -> IO(List<&2, St.Slot>):
  match insts:
    case Nil{}:
      IO.pure(List<&2, St.Slot>, [])
    case Con{+inst, rest}:
      match inst:
        case St.Slot{+url, _n}:
          do IO<List<&2, St.Slot>>:
            got : Maybe<&2, String> <- Rr.Reader.health(url)
            more : List<&2, St.Slot> <- Pool.healthy(rest)
            Pool.keep(got, inst, more)

# a shard read by worker wk, the read sent; False when the queue is drained
def Pool.step(got: Maybe<&1, S.Shard>, wk: Worker, +outs: Chan(Rd.Read), +question: String) -> IO(Bool):
  match got:
    case None{}:
      IO.pure(Bool, False{})
    case Some{sh}:
      match wk:
        case Worker{_id, url, slot}:
          do IO<Bool>:
            rd : Rd.Read <- Rr.Reader.call(url, slot, sh, question)
            _sent : Result<&1, &1, Rd.Read, Unit> <- Chan.send(Rd.Read, outs, rd)
            return True{}

# go on when more, else stop
def Pool.again(more: Bool, next: Unit -> IO(Unit)) -> IO(Unit):
  match more:
    case True{}:
      next(Unit{})
    case False{}:
      IO.pure(Unit, Unit{})

# a worker: read shards from the closed queue of cnt shards until it is
# drained; it can take no more than cnt
def Pool.work(
  cnt: Nat,
  +wk: Worker,
  +jobs: Chan(S.Shard),
  +outs: Chan(Rd.Read),
  +question: String
) -> IO(Unit):
  match cnt:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+more:
      do IO<Unit>:
        got : Maybe<&1, S.Shard> <- Chan.recv(S.Shard, jobs)
        go : Bool <- Pool.step(got, wk, outs, question)
        Pool.again(go, _u => Pool.work(more, wk, jobs, outs, question))

# the read ahead of done, when one came
def Pool.done(got: Maybe<&1, Rd.Read>, done: List<&2, Rd.Read>) -> List<&2, Rd.Read>:
  match got:
    case None{}:
      done
    case Some{rd}:
      rd <> done

# the next cnt reads to arrive
def Pool.gather(cnt: Nat, +outs: Chan(Rd.Read), done: List<&2, Rd.Read>) -> IO(List<&2, Rd.Read>):
  match cnt:
    case 0n:
      IO.pure(List<&2, Rd.Read>, done)
    case 1n+more:
      do IO<List<&2, Rd.Read>>:
        got : Maybe<&1, Rd.Read> <- Chan.recv(Rd.Read, outs)
        Pool.gather(more, outs, Pool.done(got, done))

# every shard on the queue
def Pool.queue(ss: List<&2, S.Shard>, +jobs: Chan(S.Shard)) -> IO(Unit):
  match ss:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{sh, rest}:
      do IO<Unit>:
        _put : Result<&1, &1, S.Shard, Unit> <- Chan.send(S.Shard, jobs, sh)
        Pool.queue(rest, jobs)

# start a worker for each of ws on a queue of cnt shards
def Pool.fork(
  ws: List<&2, Worker>,
  +cnt: Nat,
  +jobs: Chan(S.Shard),
  +outs: Chan(Rd.Read),
  +question: String
) -> IO(List<&2, Chan(Unit)>):
  match ws:
    case Nil{}:
      IO.pure(List<&2, Chan(Unit)>, [])
    case Con{wk, rest}:
      do IO<List<&2, Chan(Unit)>>:
        ch : Chan(Unit) <- IO.fork(Unit, Pool.work(cnt, wk, jobs, outs, question))
        more : List<&2, Chan(Unit)> <- Pool.fork(rest, cnt, jobs, outs, question)
        return ch <> more

# wait for every worker to stop
def Pool.join(chs: List<&2, Chan(Unit)>) -> IO(Unit):
  match chs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{ch, rest}:
      do IO<Unit>:
        IO.join(Unit, ch)
        Pool.join(rest)

# one pass: the shards on a queue, filled and closed, read by the workers
# ws; one read per shard, in the order they finished
def Pool.pass(ws: List<&2, Worker>, +ss: List<&2, S.Shard>, +question: String) -> IO(List<&2, Rd.Read>):
  +cnt = List.length(&2, S.Shard, ss)
  +room = U32.inc(U32.from_nat(cnt))
  do IO<List<&2, Rd.Read>>:
    +jobs : Chan(S.Shard) <- Chan.new(S.Shard, room)
    +outs : Chan(Rd.Read) <- Chan.new(Rd.Read, room)
    Pool.queue(ss, jobs)
    Chan.close(S.Shard, jobs)
    chs : List<&2, Chan(Unit)> <- Pool.fork(ws, cnt, jobs, outs, question)
    reads : List<&2, Rd.Read> <- Pool.gather(cnt, outs, [])
    Pool.join(chs)
    return reads

# wk ahead of rest when it is not on the instance url
def Pool.other.if(on: Bool, wk: Worker, rest: List<&2, Worker>) -> List<&2, Worker>:
  match on:
    case True{}:
      rest
    case False{}:
      wk <> rest

# the workers that are not on the instance url
def Pool.other(ws: List<&2, Worker>, +url: String) -> List<&2, Worker>:
  match ws:
    case Nil{}:
      []
    case Con{+wk, rest}:
      match wk:
        case Worker{_id, +wurl, _slot}:
          Pool.other.if(String.eq(wurl, url), wk, Pool.other(rest, url))

# the workers of the second pass for shards failed on url: those of the
# other instances, or all when there are none
def Pool.second(others: List<&2, Worker>, ws: List<&2, Worker>) -> List<&2, Worker>:
  match others:
    case Nil{}:
      ws
    case Con{wk, rest}:
      wk <> rest

# the instances failed reads came from, each once
def Pool.insts(bad: List<&2, Rd.Read>, seen: List<&2, String>) -> List<&2, String>:
  match bad:
    case Nil{}:
      seen
    case Con{rd, rest}:
      match rd:
        case Rd.Read{_shard, inst, _labels, _ok, _why, _pn, _pm, _cn, _ms}:
          Pool.insts(rest, S.Shard.insert(seen, inst))

# True on a hit, else what later finds
def Pool.failed_on.if(hit: Bool, later: Unit -> Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      later(Unit{})

# True when a failed read of shard num came from url
def Pool.failed_on(bad: List<&2, Rd.Read>, +num: U32, +url: String) -> Bool:
  match bad:
    case Nil{}:
      False{}
    case Con{rd, rest}:
      match rd:
        case Rd.Read{+shard, +inst, _labels, _ok, _why, _pn, _pm, _cn, _ms}:
          Pool.failed_on.if(Bool.and(U32.is_eq(shard, num), String.eq(inst, url)),
            _u => Pool.failed_on(rest, num, url))

# sh ahead of rest when kept
def Pool.keep.if(keep: Bool, sh: S.Shard, rest: List<&2, S.Shard>) -> List<&2, S.Shard>:
  match keep:
    case True{}:
      sh <> rest
    case False{}:
      rest

# the shards whose read failed on url
def Pool.redo(ss: List<&2, S.Shard>, +bad: List<&2, Rd.Read>, +url: String) -> List<&2, S.Shard>:
  match ss:
    case Nil{}:
      []
    case Con{+sh, rest}:
      Pool.keep.if(Pool.failed_on(bad, Rd.Read.n(sh), url), sh, Pool.redo(rest, bad, url))

# the second pass, one instance at a time: the shards that failed on it,
# read by the workers of the others
def Pool.retry(
  insts: List<&2, String>,
  +ws: List<&2, Worker>,
  +ss: List<&2, S.Shard>,
  +bad: List<&2, Rd.Read>,
  +question: String
) -> IO(List<&2, Rd.Read>):
  match insts:
    case Nil{}:
      IO.pure(List<&2, Rd.Read>, [])
    case Con{+url, rest}:
      do IO<List<&2, Rd.Read>>:
        got : List<&2, Rd.Read> <- Pool.pass(Pool.second(Pool.other(ws, url), ws), Pool.redo(ss, bad, url), question)
        more : List<&2, Rd.Read> <- Pool.retry(rest, ws, ss, bad, question)
        return List.append(&2, Rd.Read, got, more)

# the two passes with the workers ws; with no worker, stop with exit 2.
# The second pass's reads come first, so Read.ordered takes them
def Pool.start(ws: List<&2, Worker>, +ss: List<&2, S.Shard>, +question: String) -> IO(List<&2, Rd.Read>):
  match ws:
    case Nil{}:
      IO.die(List<&2, Rd.Read>, 2, "episteme: no reader instance is healthy")
    case Con{+wk, +rest}:
      do IO<List<&2, Rd.Read>>:
        +first : List<&2, Rd.Read> <- Pool.pass(wk <> rest, ss, question)
        +bad : List<&2, Rd.Read> = Rd.Read.failed(first)
        again : List<&2, Rd.Read> <- Pool.retry(Pool.insts(bad, []), wk <> rest, ss, bad, question)
        return List.append(&2, Rd.Read, again, first)

# read every shard with the pool's healthy instances, skipping the others
# with a line on stderr; a failed read is read again on another instance
def Pool.run(insts: List<&2, St.Slot>, +ss: List<&2, S.Shard>, +question: String) -> IO(List<&2, Rd.Read>):
  do IO<List<&2, Rd.Read>>:
    ok : List<&2, St.Slot> <- Pool.healthy(insts)
    Pool.start(Pool.workers(ok, 1), ss, question)
