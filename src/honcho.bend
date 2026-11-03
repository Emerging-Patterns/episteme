# episteme/src/honcho: a Honcho message read as a record, where the next
# page of a session's messages starts, and the honcho connector's cursor.
# Pure: no IO.
import Base
import ./record.bend as R
import ./chat.bend as C
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# a message as ingest keeps it: its id, created_at, peer, workspace,
# session and content
type Msg is Data:
  Msg{id: String, ts: String, peer: String, ws: String, session: String,
    body: String}

# where a read of a session starts: a page index d (Honcho's page d + 1)
# and how many of that page's messages were read before
type Place is Data:
  Place{d: Nat, skip: Nat}

# what reading one page gives: its items not read before, and where the
# read goes on, None when it ends there
type Step is Data:
  Step{fresh: List<&2, Value.Json>, next: Maybe<&2, Place>}

# --- a message's record ---

# the messages a page asks for, the most Honcho serves
def Honcho.size() -> Nat:
  100n

# the record of a message: id honcho:<id>, its created_at, source
# chat:honcho, its peer as author, <workspace>/<session> as thread, no
# parent and no pointer, its content the body; None when the content has
# no paragraph
def Honcho.record(msg: Msg) -> Maybe<&2, R.Record>:
  match msg:
    case Msg{id, ts, peer, ws, session, body}:
      R.Record.make("honcho:" ++ id, ts, "chat:honcho", peer, ws ++ "/" ++ session,
        "", body, "")

# the records of messages, in order
def Honcho.records(ms: List<&2, Msg>) -> List<&2, R.Record>:
  match ms:
    case Nil{}:
      []
    case Con{m, rest}:
      C.Chat.put(Honcho.record(m), Honcho.records(rest))

# --- reading a message's JSON ---

# the message of the parts read, or None when one is missing
def Honcho.msg.of(
  id: Maybe<&2, String>,
  ts: Maybe<&2, String>,
  peer: Maybe<&2, String>,
  ws: Maybe<&2, String>,
  session: Maybe<&2, String>,
  body: Maybe<&2, String>
) -> Maybe<&2, Msg>:
  match id ts peer ws session body:
    case Some{i} Some{t} Some{p} Some{w} Some{s} Some{b}:
      Some{Msg{i, t, p, w, s, b}}
    case _ _ _ _ _ _:
      None{}

# a message read from its JSON object: None when id, created_at, peer_id,
# workspace_id or session_id is missing or empty, or content is not a
# string
def Honcho.msg(+js: Value.Json) -> Maybe<&2, Msg>:
  Honcho.msg.of(R.Record.full(js, "id"), R.Record.full(js, "created_at"),
    R.Record.full(js, "peer_id"), R.Record.full(js, "workspace_id"),
    R.Record.full(js, "session_id"), Json.as_str(Json.get(js, "content")))

# the message ahead of rest, when there is one
def Honcho.msg.put(got: Maybe<&2, Msg>, rest: List<&2, Msg>) -> List<&2, Msg>:
  match got:
    case None{}:
      rest
    case Some{m}:
      m <> rest

# the messages read from JSON objects, in order; an object that is no
# message is dropped
def Honcho.msgs(js: List<&2, Value.Json>) -> List<&2, Msg>:
  match js:
    case Nil{}:
      []
    case Con{+head, rest}:
      Honcho.msg.put(Honcho.msg(head), Honcho.msgs(rest))

# the items of a page's JSON text: its "items" array, or None when the
# text is not JSON or has no such array
def Honcho.items.of(got: Maybe<&2, Value.Json>) -> Maybe<&2, List<&2, Value.Json>>:
  match got:
    case None{}:
      None{}
    case Some{+js}:
      Bool.pick(Maybe<&2, List<&2, Value.Json>>, Json.is_arr(Json.get(js, "items")),
        Some{Json.items(Json.get(js, "items"))}, None{})

# the items of a page's JSON text
def Honcho.items(text: String) -> Maybe<&2, List<&2, Value.Json>>:
  Honcho.items.of(Json.parse(text))

# the id ahead of rest, when there is one
def Honcho.id.put(got: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match got:
    case None{}:
      rest
    case Some{id}:
      id <> rest

# the ids of a list page's items (workspaces or sessions), those that have
# a non-empty one
def Honcho.ids(js: List<&2, Value.Json>) -> List<&2, String>:
  match js:
    case Nil{}:
      []
    case Con{+head, rest}:
      Honcho.id.put(R.Record.full(head, "id"), Honcho.ids(rest))

# --- paging ---

# the place of a quotient and remainder
def Honcho.place.of(qr: Nat & Nat) -> Place:
  match qr:
    case (q, r):
      Place{q, r}

# where the read of a session past its first n messages starts: the page
# index n / size (Honcho's page n / size + 1) and the skip n mod size
def Honcho.place(count: Nat) -> Place:
  Honcho.place.of(Nat.divmod(count, Honcho.size()))

# the query of page index d: ?page=<d + 1>&size=<size>
def Honcho.query(idx: Nat) -> String:
  "?page=" ++ Nat.show(1n+idx) ++ "&size=" ++ Nat.show(Honcho.size())

# the items of a page not read before: those after the first skip
def Honcho.fresh(skip: Nat, items: List<&2, Value.Json>) -> List<&2, Value.Json>:
  List.drop(&2, Value.Json, items, skip)

# True when a page holds Honcho.size() items, so another may follow
def Honcho.full(items: List<&2, Value.Json>) -> Bool:
  Nat.is_eq(List.length(&2, Value.Json, items), Honcho.size())

# where the read goes on after a page of index d: after a full page, the
# next page from its start; after any other, nowhere
def Honcho.step.next(full: Bool, idx: Nat) -> Maybe<&2, Place>:
  match full:
    case True{}:
      Some{Place{1n+idx, 0n}}
    case False{}:
      None{}

# reading the items of the page at place (d, skip): its items after the
# first skip, and where the read goes on
def Honcho.step(place: Place, +items: List<&2, Value.Json>) -> Step:
  match place:
    case Place{d, skip}:
      Step{Honcho.fresh(skip, items), Honcho.step.next(Honcho.full(items), d)}

# --- the model of a session's list ---

# a session's messages from page index d on, as Honcho serves them: all
# of them, less Honcho.size() for each page before
def Honcho.from(all: List<&2, Value.Json>, idx: Nat) -> List<&2, Value.Json>:
  match idx:
    case 0n:
      all
    case 1n+k:
      List.drop(&2, Value.Json, Honcho.from(all, k), Honcho.size())

# the page of index d of a session's messages
def Honcho.page(all: List<&2, Value.Json>, idx: Nat) -> List<&2, Value.Json>:
  List.take(&2, Value.Json, Honcho.from(all, idx), Honcho.size())

# the items a read gets past where a step left it: none when it ended
def Honcho.walk.next(got: Maybe<&2, Place>, go: Place -> List<&2, Value.Json>) -> List<&2, Value.Json>:
  match got:
    case None{}:
      []
    case Some{place}:
      go(place)

# a step's fresh items, then the rest of the read
def Honcho.walk.then(st: Step, go: Place -> List<&2, Value.Json>) -> List<&2, Value.Json>:
  match st:
    case Step{fresh, next}:
      List.append(&2, Value.Json, fresh, Honcho.walk.next(next, go))

# the items a read of all from place gets, as the shell reads a session:
# step after step, at most fuel pages
def Honcho.walk(fuel: Nat, +all: List<&2, Value.Json>, place: Place) -> List<&2, Value.Json>:
  match fuel:
    case 0n:
      []
    case 1n+f:
      match place:
        case Place{+d, skip}:
          Honcho.walk.then(Honcho.step(Place{d, skip}, Honcho.page(all, d)),
            p => Honcho.walk(f, all, p))

# --- the cursor ---

# the cursor's entries, one "<n>\t<thread>" line per session read, n the
# session's messages read, as Chat.cursor reads them; a line that is no
# entry is dropped. Chat.cursor.get, set and text read, change and write it
def Honcho.cursor(text: String) -> List<&2, C.Seen>:
  C.Chat.cursor(text)
