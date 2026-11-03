# episteme/src/conn/honcho: the Honcho raw message connector. It reads
# Honcho at $HONCHO_BASE_URL (default http://127.0.0.1:8000) with the key
# $HONCHO_API_KEY, through these v3 endpoints only, each a read-only list
# POST with the body {} and Honcho.query (served paths checked
# against GET /openapi.json on 2026-10-31):
#   POST /v3/workspaces/list
#   POST /v3/workspaces/{workspace_id}/sessions/list
#   POST /v3/workspaces/{workspace_id}/sessions/{session_id}/messages/list
# It never reads conclusions, representations, peer cards, dreams or
# summaries, and never writes to Honcho. Records go to the log in batches
# of whole sessions, about Honcho.budget() code points each, each batch
# carrying the cursor after its sessions. What a message becomes and where
# a session's next read starts is src/honcho.bend. IO: the trusted shell.
#
# Trusted, not proved: `episteme ingest honcho` reads its cursor with
# `Store.cursor("honcho")` (`Honcho.cursor`, laws/HonchoRecordFields.bend) and
# talks to Honcho at `$HONCHO_BASE_URL` (default `http://127.0.0.1:8000`) with the
# bearer key `$HONCHO_API_KEY`, using only the read-only list calls of the v3
# API, each a `POST` with the body `{}` and the query `Honcho.query(d)`, a
# 60000 ms timeout and ezhttp's `http.post_opts`: `/v3/workspaces/list`, then
# for each workspace `/v3/workspaces/<w>/sessions/list`, then for each session
# `/v3/workspaces/<w>/sessions/<s>/messages/list`, ids path-quoted. It never
# reads conclusions, representations, peer cards, dreams or summaries, and
# never writes. Every list is read as `Honcho.walk` reads its model: from
# `Honcho.place(n)`, `n` the session's count in the cursor (0 for none, and
# for the workspace and session lists), each page's `Honcho.step` giving its
# fresh items and where to go on, until a step ends the read or 1,000,000
# pages were read; fresh messages are read with `Honcho.msg` and
# `Honcho.record`, and the session's count becomes `n` plus its fresh items.
# It assumes Honcho serves a session's messages as the model of
# laws/HonchoReadsOnlyNew.bend says: page `p` with `size=100` is items `(p -
# 1) * 100` to `p * 100` of one list in creation order that only grows at its
# end (the v3 API has no call that deletes one message); a message deleted
# from a session read before shifts the counts after it. A call that fails (a
# transport error, a status other than 200, or a body with no `items` array)
# is reported on stderr: a failed workspace list stops the run with exit 1 and
# nothing appended, a failed session list skips that workspace, and a failed
# page skips that session, its count left as it was. Sessions are gathered
# whole, in list order, until their records reach `Honcho.budget()`
# (4,000,000) code points of shard size, and then appended with one
# `Ingest.run`, whose batch carries the cursor with every gathered session's
# count; the rest go in one last `Ingest.run`. It prints each batch's count
# and the total records and messages read. A message is given once: its record
# and the cursor that counts it are in one batch.
#
# Why it is trusted: It is HTTP through ezhttp's client, which no law reaches
# (ezhttp's own gate trusts its wire effect, on its src/client.bend and
# src/wire.bend); what a message becomes and where a read starts is
# laws/HonchoRecordFields.bend, laws/HonchoStepPages.bend and
# laws/HonchoReadsOnlyNew.bend. `tests/smoke.sh` runs it against
# `tests/fixtures/honcho/serve.py`, a fake Honcho serving synthetic messages,
# which refuses every call but a list `POST`: the record count with a session
# of 250 messages read over three pages and messages of one `created_at`
# across a page boundary, a session at a partial page grown by more than a
# page, the authors and threads, a message with empty content giving no
# record, a second run that reads nothing, and messages added later read once.
import Base
import ../record.bend as R
import ../chat.bend as C
import ../honcho.bend as H
import ../store.bend as St
import ../ingest.bend as In
import 0x8abe7473e8854cc69c687ee77b7d72e3/main.bend as Sys
import 0xedb2120a04a47dc18c3a756ec7c62750/main.bend as Ez
import 0xedb2120a04a47dc18c3a756ec7c62750/src/http.bend as Http
import 0xedb2120a04a47dc18c3a756ec7c62750/src/client.bend as Client
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# how far a run got: the cursor, the records read and not yet appended
# (newest session first), their code points, the records appended and the
# messages read so far, and the batches appended
type Run is Data:
  Run{pos: List<&2, C.Seen>, recs: List<&2, List<&2, R.Record>>,
    chars: Nat, total: U32, msgs: U32, batches: U32}

# where Honcho is and the key it takes
type Api is Data:
  Api{base: String, key: String}

# the code points of records a batch gathers before it is appended
def Honcho.budget() -> Nat:
  4000000n

# how long one call may take, in milliseconds
def Honcho.timeout() -> U32:
  60000

# --- calls ---

# the items, or None, said on stderr, when the body had none
def Honcho.took.items(got: Maybe<&2, List<&2, Value.Json>>, +what: String) -> IO(Maybe<&2, List<&2, Value.Json>>):
  match got:
    case None{}:
      do IO<Maybe<&2, List<&2, Value.Json>>>:
        IO.print_err("episteme: honcho " ++ what ++ ": no items array")
        return None{}
    case Some{items}:
      IO.pure(Maybe<&2, List<&2, Value.Json>>, Some{items})

# the items of a 200 answer's body, else None, said on stderr
def Honcho.took.status(ok: Bool, status: U32, body: String, +what: String) -> IO(Maybe<&2, List<&2, Value.Json>>):
  match ok:
    case False{}:
      do IO<Maybe<&2, List<&2, Value.Json>>>:
        IO.print_err("episteme: honcho " ++ what ++ ": HTTP " ++ U32.show(status))
        return None{}
    case True{}:
      Honcho.took.items(H.Honcho.items(body), what)

# a page's items, or None, said on stderr, when the call failed
def Honcho.took(res: Client.Response, +what: String) -> IO(Maybe<&2, List<&2, Value.Json>>):
  match res:
    case Client.Err{why}:
      do IO<Maybe<&2, List<&2, Value.Json>>>:
        IO.print_err("episteme: honcho " ++ what ++ ": " ++ why)
        return None{}
    case Client.Response{+status, _headers, _reason, bytes}:
      Honcho.took.status(U32.is_eq(status, 200), status, Ez.body_text(bytes), what)

# the items of page index d of a list endpoint, or None when the call
# failed
def Honcho.call(+api: Api, +path: String, idx: Nat) -> IO(Maybe<&2, List<&2, Value.Json>>):
  match api:
    case Api{+base, +key}:
      do IO<Maybe<&2, List<&2, Value.Json>>>:
        +what : String = path ++ H.Honcho.query(idx)
        res : Client.Response <- Ez.http.post_opts(base ++ what,
          [Http.H{"Content-Type", "application/json"}, Ez.bearer(key)],
          Ez.text_body("{}"), Honcho.timeout())
        Honcho.took(res, what)

# --- reading a list ---

# the most pages one read takes: 100,000,000 items
def Honcho.fuel() -> Nat:
  1000000n

# None, said on stderr, when a read took Honcho.fuel() pages
def Honcho.spent(+path: String) -> IO(Maybe<&2, List<&2, Value.Json>>):
  do IO<Maybe<&2, List<&2, Value.Json>>>:
    IO.print_err("episteme: honcho " ++ path ++ ": more than " ++ Nat.show(Honcho.fuel())
      ++ " pages")
    return None{}

# the fresh items of the pages read so far (newest page first), with the
# rest of the read, which go gives, when the step goes on
def Honcho.read.next(
  next: Maybe<&2, H.Place>,
  acc: List<&2, List<&2, Value.Json>>,
  go: H.Place -> List<&2, List<&2, Value.Json>> -> IO(Maybe<&2, List<&2, Value.Json>>)
) -> IO(Maybe<&2, List<&2, Value.Json>>):
  match next:
    case Some{place}:
      go(place, acc)
    case None{}:
      IO.pure(Maybe<&2, List<&2, Value.Json>>, Some{List.concat(&2, Value.Json,
        List.reverse(&2, List<&2, Value.Json>, acc))})

# the read after a page's step, or None when the call failed
def Honcho.read.step(
  got: Maybe<&2, H.Step>,
  acc: List<&2, List<&2, Value.Json>>,
  go: H.Place -> List<&2, List<&2, Value.Json>> -> IO(Maybe<&2, List<&2, Value.Json>>)
) -> IO(Maybe<&2, List<&2, Value.Json>>):
  match got:
    case None{}:
      IO.pure(Maybe<&2, List<&2, Value.Json>>, None{})
    case Some{st}:
      match st:
        case H.Step{fresh, next}:
          Honcho.read.next(next, fresh <> acc, go)

# a page's step at place, or None when the call failed
def Honcho.stepped(+place: H.Place, got: Maybe<&2, List<&2, Value.Json>>) -> Maybe<&2, H.Step>:
  match got:
    case None{}:
      None{}
    case Some{+items}:
      Some{H.Honcho.step(place, items)}

# the items of a list endpoint from place on, read as Honcho.walk reads
# its model (laws/HonchoReadsOnlyNew.bend), or None when a call failed or fuel pages were read
def Honcho.read(
  fuel: Nat,
  +api: Api,
  +path: String,
  +place: H.Place,
  acc: List<&2, List<&2, Value.Json>>
) -> IO(Maybe<&2, List<&2, Value.Json>>):
  match fuel:
    case 0n:
      Honcho.spent(path)
    case 1n+left:
      match place:
        case H.Place{+d, skip}:
          do IO<Maybe<&2, List<&2, Value.Json>>>:
            got : Maybe<&2, List<&2, Value.Json>> <- Honcho.call(api, path, d)
            Honcho.read.step(Honcho.stepped(H.Place{d, skip}, got), acc,
              p => more => Honcho.read(left, api, path, p, more))

# the ids of a list endpoint's items, or None when a call failed
def Honcho.ids.of(got: Maybe<&2, List<&2, Value.Json>>) -> Maybe<&2, List<&2, String>>:
  match got:
    case None{}:
      None{}
    case Some{items}:
      Some{H.Honcho.ids(items)}

# the ids of every item of a list endpoint, or None when a call failed
def Honcho.list(+api: Api, +path: String) -> IO(Maybe<&2, List<&2, String>>):
  do IO<Maybe<&2, List<&2, String>>>:
    got : Maybe<&2, List<&2, Value.Json>> <- Honcho.read(Honcho.fuel(), api, path, H.Honcho.place(0n), [])
    return Honcho.ids.of(got)

# --- the run ---

# print how many records a batch appended, when it appended any
def Honcho.said(none: Bool, num: U32) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.print("chat:honcho: " ++ U32.show(num) ++ " records appended")

# the records gathered, oldest session first
def Honcho.gathered(recs: List<&2, List<&2, R.Record>>) -> List<&2, R.Record>:
  List.concat(&2, R.Record, List.reverse(&2, List<&2, R.Record>, recs))

# append the records gathered as one batch with the cursor; the run after
def Honcho.flush(run: Run) -> IO(Run):
  match run:
    case Run{+pos, recs, _chars, total, msgs, batches}:
      do IO<Run>:
        +n : U32 <- In.Ingest.run("honcho", Honcho.gathered(recs), C.Chat.cursor.text(pos))
        Honcho.said(U32.is_eq(n, 0), n)
        return Run{pos, [], 0n, U32.add(total, n), msgs, U32.inc(batches)}

# the run, flushed when its records reach the budget
def Honcho.flush.if(full: Bool, run: Run) -> IO(Run):
  match full:
    case True{}:
      Honcho.flush(run)
    case False{}:
      IO.pure(Run, run)

# the run after a session's fresh items, its first n read before: their
# records gathered and the session's count set to n plus them
def Honcho.take(run: Run, +thread: String, count: U32, +items: List<&2, Value.Json>) -> IO(Run):
  match run:
    case Run{pos, recs, chars, total, msgs, batches}:
      +made : List<&2, R.Record> = H.Honcho.records(H.Honcho.msgs(items))
      +more : Nat = Nat.add(chars, C.Chat.chars(made))
      +read : U32 = U32.from_nat(List.length(&2, Value.Json, items))
      Honcho.flush.if(Nat.is_le(Honcho.budget(), more),
        Run{C.Chat.cursor.set(pos, thread, U32.add(count, read)), made <> recs, more, total,
          U32.add(msgs, read), batches})

# the run after a session read, unchanged, said on stderr, when it failed
def Honcho.session.got(
  got: Maybe<&2, List<&2, Value.Json>>,
  run: Run,
  +thread: String,
  count: U32
) -> IO(Run):
  match got:
    case None{}:
      do IO<Run>:
        IO.print_err("episteme: honcho session " ++ thread ++ " skipped")
        return run
    case Some{items}:
      Honcho.take(run, thread, count, items)

# the run after a session of a workspace
def Honcho.session(run: Run, +api: Api, +ws: String, +session: String) -> IO(Run):
  match run:
    case Run{+pos, recs, chars, total, msgs, batches}:
      do IO<Run>:
        +thread : String = ws ++ "/" ++ session
        +n : U32 = C.Chat.cursor.get(pos, thread)
        got : Maybe<&2, List<&2, Value.Json>> <- Honcho.read(Honcho.fuel(), api,
          "/v3/workspaces/" ++ Ez.quote_path(ws) ++ "/sessions/" ++ Ez.quote_path(session)
            ++ "/messages/list",
          H.Honcho.place(U32.to_nat(n)), [])
        Honcho.session.got(got, Run{pos, recs, chars, total, msgs, batches}, thread, n)

# the run after each session, in order
def Honcho.sessions(ss: List<&2, String>, run: Run, +api: Api, +ws: String) -> IO(Run):
  match ss:
    case Nil{}:
      IO.pure(Run, run)
    case Con{+session, rest}:
      do IO<Run>:
        next : Run <- Honcho.session(run, api, ws, session)
        Honcho.sessions(rest, next, api, ws)

# the run after a workspace's sessions, unchanged, said on stderr, when
# they cannot be listed
def Honcho.workspace.got(got: Maybe<&2, List<&2, String>>, run: Run, +api: Api, +ws: String) -> IO(Run):
  match got:
    case None{}:
      do IO<Run>:
        IO.print_err("episteme: honcho workspace " ++ ws ++ " skipped")
        return run
    case Some{ss}:
      Honcho.sessions(ss, run, api, ws)

# the run after every workspace, in order
def Honcho.workspaces(wss: List<&2, String>, run: Run, +api: Api) -> IO(Run):
  match wss:
    case Nil{}:
      IO.pure(Run, run)
    case Con{+ws, rest}:
      do IO<Run>:
        got : Maybe<&2, List<&2, String>> <- Honcho.list(api,
          "/v3/workspaces/" ++ Ez.quote_path(ws) ++ "/sessions/list")
        next : Run <- Honcho.workspace.got(got, run, api, ws)
        Honcho.workspaces(rest, next, api)

# print a run's total
def Honcho.done(run: Run) -> IO(Unit):
  match run:
    case Run{_pos, _recs, _chars, total, msgs, _batches}:
      IO.print("chat:honcho: " ++ U32.show(total) ++ " records, " ++ U32.show(msgs)
        ++ " messages read")

# the run over every workspace, its last records appended; or, when the
# workspaces cannot be listed, nothing appended and exit 1
def Honcho.all(got: Maybe<&2, List<&2, String>>, run: Run, +api: Api) -> IO(Unit):
  match got:
    case None{}:
      do IO<Unit>:
        IO.print_err("episteme: honcho: cannot list workspaces; nothing appended")
        St.Store.exit(1)
    case Some{wss}:
      do IO<Unit>:
        ran : Run <- Honcho.workspaces(wss, run, api)
        last : Run <- Honcho.flush(ran)
        Honcho.done(last)

# ingest every Honcho message not yet read, in batches of whole sessions;
# prints each batch's count, then the total
def Honcho.run() -> IO(Unit):
  do IO<Unit>:
    base : String <- Sys.env.or("HONCHO_BASE_URL", "http://127.0.0.1:8000")
    key : String <- Sys.env.or("HONCHO_API_KEY", "")
    +api : Api = Api{base, key}
    cursor : String <- St.Store.cursor("honcho")
    got : Maybe<&2, List<&2, String>> <- Honcho.list(api, "/v3/workspaces/list")
    Honcho.all(got, Run{H.Honcho.cursor(cursor), [], 0n, 0, 0, 0}, api)
