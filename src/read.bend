# episteme/src/read: what a reader is asked, what its reply means, which
# failed read is tried again, and what `ask` prints about a run. A failed
# call is never an empty answer: only a reply naming an ids array is ok.
# Pure: no IO.
import Base
import ./record.bend as R
import ./shard.bend as S
import ./excerpt.bend as E
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# one reader call: the shard it read, the instance that read it, the labels
# it named, whether it answered (False when the call failed, which is never
# an empty answer), why it failed, and the server's timings: prompt tokens
# processed, their milliseconds, prompt tokens reused from the cache, and
# the call's milliseconds (prompt and generation)
type Read is Data:
  Read{shard: U32, inst: String, labels: List<&2, String>, ok: Bool,
    why: String, prompt_n: U32, prompt_ms: U32, cache_n: U32, ms: U32}

# --- the request ---

# the reader's system prompt
def Read.prompt() -> String:
  "You read one slice of a record and find every paragraph that could help answer a question. Each paragraph starts with a label in square brackets, like [p12]. Return the labels of every paragraph that is plausibly related to the question: direct answers, definitions, background, examples, and anything mentioning the same people, terms or events. When unsure, include it. If nothing is related, return an empty list. Return only labels that appear in the text."

# the labels p<idx> to p<idx + cnt - 1> as JSON strings
def Read.enum(cnt: Nat, +idx: U32) -> List<&2, Value.Json>:
  match cnt:
    case 0n:
      []
    case 1n+more:
      Json.str(S.Shard.label(idx)) <> Read.enum(more, U32.inc(idx))

# the response format for a shard of cnt paragraphs: an object whose ids
# are at most cnt of its own labels p1 to p<cnt>, so the grammar admits no
# other label
def Read.schema(+cnt: Nat) -> Value.Json:
  Json.obj([("type", Json.str("json_schema")),
    ("json_schema", Json.obj([("schema", Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("ids", Json.obj([
        ("type", Json.str("array")),
        ("items", Json.obj([("enum", Json.arr(Read.enum(cnt, 1)))])),
        ("maxItems", Json.num(Nat.show(cnt)))]))])),
      ("required", Json.arr([Json.str("ids")]))]))]))])

# a chat message
def Read.message(role: String, content: String) -> Value.Json:
  Json.obj([("role", Json.str(role)), ("content", Json.str(content))])

# the messages: the prompt, then the shard, then the question, so the
# shard is the prefix every question shares
def Read.messages(sh: S.Shard, question: String) -> List<&2, Value.Json>:
  [Read.message("system", Read.prompt()),
    Read.message("user", S.Shard.render(sh)),
    Read.message("user", "Question: " ++ question)]

# how many paragraphs a shard holds: one label each
def Read.paras(sh: S.Shard) -> Nat:
  List.length(&2, S.Shard.Label(), S.Shard.labels(sh))

# the most tokens a reply may take for cnt paragraphs: enough for every
# label, 6 a paragraph, and 64 more, plus 512 for the reader's thinking,
# which deploy/reader.sh caps at 512 (a thinking model thinks whatever the
# request says, and one that cannot think lists every paragraph)
def Read.max_tokens(cnt: Nat) -> U32:
  U32.add(U32.mul(6, U32.from_nat(cnt)), 576)

# the body of POST /v1/chat/completions for a shard and a question, on a
# slot of the instance
def Read.request(slot: U32, +sh: S.Shard, question: String) -> Value.Json:
  +cnt = Read.paras(sh)
  Json.obj([("messages", Json.arr(Read.messages(sh, question))),
    ("temperature", Json.num("0")), ("max_tokens", Json.num(U32.show(Read.max_tokens(cnt)))),
    ("cache_prompt", Json.bool(True{})),
    ("id_slot", Json.num(U32.show(slot))),
    ("chat_template_kwargs", Json.obj([("enable_thinking", Json.bool(False{}))])),
    ("response_format", Read.schema(cnt))])

# --- the reply ---

# a string ahead of more, or None when either is missing
def Read.strs.cons(got: Maybe<&2, String>, more: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match got more:
    case Some{x} Some{xs}:
      Some{x <> xs}
    case _ _:
      None{}

# the strings of JSON values, or None when one is not a string
def Read.strs(js: List<&2, Value.Json>) -> Maybe<&2, List<&2, String>>:
  match js:
    case Nil{}:
      Some{[]}
    case Con{head, rest}:
      Read.strs.cons(Json.as_str(head), Read.strs(rest))

# the strings of an array, or None when it is no array
def Read.arr.if(arr: Bool, js: Value.Json) -> Maybe<&2, List<&2, String>>:
  match arr:
    case True{}:
      Read.strs(Json.items(js))
    case False{}:
      None{}

# an array of strings, or None when it is not one
def Read.arr(+js: Value.Json) -> Maybe<&2, List<&2, String>>:
  Read.arr.if(Json.is_arr(js), js)

# the ids of a parsed answer, or None
def Read.answer.of(got: Maybe<&2, Value.Json>) -> Maybe<&2, List<&2, String>>:
  match got:
    case None{}:
      None{}
    case Some{js}:
      Read.arr(Json.get(js, "ids"))

# the ids of the reader's answer {"ids": [...]}, or None when it is not
# JSON or its ids is not an array of strings
def Read.answer(content: Maybe<&2, String>) -> Maybe<&2, List<&2, String>>:
  match content:
    case None{}:
      None{}
    case Some{text}:
      Read.answer.of(Json.parse(text))

# the content of a chat completion's first choice, or None
def Read.content(js: Value.Json) -> Maybe<&2, String>:
  Json.as_str(Json.get(Json.get(Json.at(Json.get(js, "choices"), 0), "message"), "content"))

# the first piece read as a U32, or 0
def Read.num.whole(ps: List<&2, String>) -> U32:
  match ps:
    case Nil{}:
      0
    case Con{head, _rest}:
      Maybe.default(&2, U32, U32.read(head), 0)

# a JSON number's whole part as a U32, or 0
def Read.num.raw(got: Maybe<&2, String>) -> U32:
  match got:
    case None{}:
      0
    case Some{raw}:
      Read.num.whole(String.split(raw, '.'))

# a timing in whole units: the number's digits before any point, 0 when
# there is none
def Read.num(+tm: Value.Json, key: String) -> U32:
  Read.num.raw(Json.as_num(Json.get(tm, key)))

# a line feed or carriage return as a space, any other code point as it is
def Read.flat(chr: Char) -> Char:
  match chr:
    case Chr{+code}:
      Bool.pick(Char, Bool.or(U32.is_eq(code, 10), U32.is_eq(code, 13)), Chr{32}, Chr{code})

# at most n code points of a text on one line, "..." when it was longer
def Read.clip.go(str: String, cnt: Nat) -> String:
  match str cnt:
    case SNil{} _:
      ""
    case SCon{_c, _rest} 0n:
      "..."
    case SCon{c, rest} 1n+k:
      SCon{Read.flat(c), Read.clip.go(rest, k)}

# a reply's text cut for a reason line
def Read.clip(sh: String) -> String:
  Read.clip.go(sh, 300n)

# a failed read: no labels, ok False, and why
def Read.fail(shard: U32, inst: String, why: String) -> Read:
  Read{shard, inst, [], False{}, why, 0, 0, 0, 0}

# the read of a 200 reply's ids: ok with them and the timings, or failed
# when there are none
def Read.got(
  ids: Maybe<&2, List<&2, String>>,
  shard: U32,
  inst: String,
  +tm: Value.Json,
  text: String
) -> Read:
  match ids:
    case None{}:
      Read.fail(shard, inst, "the reply holds no ids: " ++ Read.clip(text))
    case Some{ls}:
      Read{shard, inst, ls, True{}, "", Read.num(tm, "prompt_n"),
        Read.num(tm, "prompt_ms"), Read.num(tm, "cache_n"),
        U32.add(Read.num(tm, "prompt_ms"), Read.num(tm, "predicted_ms"))}

# the read of a 200 reply's parsed body, or failed when it is not JSON
def Read.parsed(got: Maybe<&2, Value.Json>, shard: U32, inst: String, +text: String) -> Read:
  match got:
    case None{}:
      Read.fail(shard, inst, "the reply is not JSON: " ++ Read.clip(text))
    case Some{+js}:
      Read.got(Read.answer(Read.content(js)), shard, inst, Json.get(js, "timings"), text)

# the read of a reply by whether its status is 200
def Read.reply.if(ok: Bool, shard: U32, inst: String, status: U32, +text: String) -> Read:
  match ok:
    case True{}:
      Read.parsed(Json.parse(text), shard, inst, text)
    case False{}:
      Read.fail(shard, inst, "HTTP " ++ U32.show(status) ++ ": " ++ Read.clip(text))

# the read of a reply's status and body: ok only for a 200 whose first
# choice's content is {"ids": [<string>, ...]}, else failed
def Read.reply(shard: U32, inst: String, +status: U32, text: String) -> Read:
  Read.reply.if(U32.is_eq(status, 200), shard, inst, status, text)

# --- the pool ---

# whether a read is ok
def Read.ok(rd: Read) -> Bool:
  match rd:
    case Read{_shard, _inst, _labels, ok, _why, _pn, _pm, _cn, _ms}:
      ok

# --- the run ---

# r ahead of rest when it failed
def Read.failed.if(ok: Bool, rd: Read, rest: List<&2, Read>) -> List<&2, Read>:
  match ok:
    case True{}:
      rest
    case False{}:
      rd <> rest

# the failed reads, in order
def Read.failed(rs: List<&2, Read>) -> List<&2, Read>:
  match rs:
    case Nil{}:
      []
    case Con{+r, rest}:
      Read.failed.if(Read.ok(r), r, Read.failed(rest))

# 1 when a read failed, else the code of the rest
def Read.code.if(ok: Bool, rest: Unit -> U32) -> U32:
  match ok:
    case True{}:
      rest(Unit{})
    case False{}:
      1

# the exit code of a run: 1 when some read failed, else 0
def Read.code(rs: List<&2, Read>) -> U32:
  match rs:
    case Nil{}:
      0
    case Con{r, rest}:
      Read.code.if(Read.ok(r), _u => Read.code(rest))

# True when excerpts of chars code points fit the budget of budget tokens
# at per / 100 characters a token
def Read.fits(chars: Nat, budget: U32, per: U32) -> Bool:
  Nat.is_le(chars, Nat.div(Nat.mul(U32.to_nat(budget), U32.to_nat(per)), 100n))

# a shard's number
def Read.n(sh: S.Shard) -> U32:
  match sh:
    case S.Shard{n, _items, _sources, _chars, _frozen}:
      n

# rd when it is the one, else what later finds
def Read.find.if(hit: Bool, rd: Read, later: Unit -> Maybe<&2, Read>) -> Maybe<&2, Read>:
  match hit:
    case True{}:
      Some{rd}
    case False{}:
      later(Unit{})

# the read of shard num, or None
def Read.find(+num: U32, rs: List<&2, Read>) -> Maybe<&2, Read>:
  match rs:
    case Nil{}:
      None{}
    case Con{+rd, rest}:
      match rd:
        case Read{+shard, _inst, _labels, _ok, _why, _pn, _pm, _cn, _ms}:
          Read.find.if(U32.is_eq(shard, num), rd, _u => Read.find(num, rest))

# a found read ahead of rest, or a failed read of shard num when none was
# found: a shard is never unread
def Read.ordered.put(got: Maybe<&2, Read>, num: U32, rest: List<&2, Read>) -> List<&2, Read>:
  match got:
    case None{}:
      Read.fail(num, "", "no read") <> rest
    case Some{rd}:
      rd <> rest

# one read per shard, in the shards' order: the first read of its number,
# or a failed read when there is none
def Read.ordered(ss: List<&2, S.Shard>, +rs: List<&2, Read>) -> List<&2, Read>:
  match ss:
    case Nil{}:
      []
    case Con{sh, rest}:
      +num = Read.n(sh)
      Read.ordered.put(Read.find(num, rs), num, Read.ordered(rest, rs))

# the labels to resolve on a shard: those of its read when it is ok, none
# when it failed or has no read
def Read.labels(got: Maybe<&2, Read>) -> List<&2, String>:
  match got:
    case None{}:
      []
    case Some{r}:
      match r:
        case Read{_shard, _inst, labels, ok, _why, _pn, _pm, _cn, _ms}:
          Bool.pick(List<&2, String>, ok, labels, [])

# a shard's resolved excerpts and unknown labels ahead of the rest's
def Read.excerpts.add(
  got: List<&2, E.Ex> & U32,
  more: List<&2, List<&2, E.Ex>> & U32
) -> List<&2, List<&2, E.Ex>> & U32:
  (xs, k) = got
  (ys, total) = more
  (xs <> ys, U32.add(k, total))

# each shard's excerpts, in the shards' order, and the count of labels
# the shards do not have
def Read.excerpts(ss: List<&2, S.Shard>, +rs: List<&2, Read>) -> List<&2, List<&2, E.Ex>> & U32:
  match ss:
    case Nil{}:
      ([], 0)
    case Con{+s, rest}:
      Read.excerpts.add(E.Excerpt.resolve(s, Read.labels(Read.find(Read.n(s), rs))),
        Read.excerpts(rest, rs))

# milliseconds as seconds with one decimal
def Read.secs(+ms: Nat) -> String:
  Nat.show(Nat.div(ms, 1000n)) ++ "." ++ Nat.show(Nat.div(Nat.mod(ms, 1000n), 100n))

# a shard's own name: its source and its number within that source. A
# run numbers the shards it reads 1, 2, ... so that reads match shards;
# names[k - 1] is the name of the run's shard k
type Name is Data:
  Name{source: String, n: U32}

# --- the run notice ---

# a shard's name as an object: its source and its own number
def Read.notice.name(nm: Name) -> Value.Json:
  match nm:
    case Name{source, n}:
      Json.obj([("source", Json.str(source)), ("n", Json.num(U32.show(n)))])

# the names as objects, in order
def Read.notice.names(names: List<&2, Name>) -> List<&2, Value.Json>:
  match names:
    case Nil{}:
      []
    case Con{nm, rest}:
      Read.notice.name(nm) <> Read.notice.names(rest)

# the body of POST <url>/v1/episteme/run before a run's reads: the question
# and the names of every shard the run reads, so a reader that ranks across
# shards fills one budget for the run
def Read.notice(names: List<&2, Name>, question: String) -> Value.Json:
  Json.obj([("question", Json.str(question)), ("shards", Json.arr(Read.notice.names(names)))])

# --- the named read ---

# a call to a reader: the path posted to and its body
type Call is Data:
  Call{path: String, body: Value.Json}

# whether a parsed notice answer says the reader ranked the run
def Read.ranked.of(got: Maybe<&2, Value.Json>) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{js}:
      Maybe.default(&2, Bool, Json.as_bool(Json.get(js, "ranked")), False{})

# Read.ranked once its status is known to be 200 or not
def Read.ranked.if(ok: Bool, text: String) -> Bool:
  match ok:
    case True{}:
      Read.ranked.of(Json.parse(text))
    case False{}:
      False{}

# whether the answer to a run notice, by its status and body, says the
# reader ranked the whole run: a 200 whose JSON ranked is true
def Read.ranked(+status: U32, text: String) -> Bool:
  Read.ranked.if(U32.is_eq(status, 200), text)

# the body of POST <url>/v1/episteme/read: the question and a shard's own
# name, for a reader that ranked the run
def Read.named(nm: Name, question: String) -> Value.Json:
  match nm:
    case Name{source, n}:
      Json.obj([("question", Json.str(question)), ("source", Json.str(source)),
        ("n", Json.num(U32.show(n)))])

# the call that reads the run's shard sh, named nm, on an instance's slot:
# by name when the instance ranked the run, else the chat request
def Read.call(ranked: Bool, slot: U32, sh: S.Shard, nm: Name, question: String) -> Call:
  match ranked:
    case True{}:
      Call{"/v1/episteme/read", Read.named(nm, question)}
    case False{}:
      Call{"/v1/chat/completions", Read.request(slot, sh, question)}

# nm when it is the one, else what later finds
def Read.name.if(hit: Bool, nm: Name, later: Unit -> Name) -> Name:
  match hit:
    case True{}:
      nm
    case False{}:
      later(Unit{})

# the name of the run's shard num among names, the first counting as idx;
# the source "" and num itself when there is none
def Read.name(names: List<&2, Name>, +num: U32, +idx: U32) -> Name:
  match names:
    case Nil{}:
      Name{"", num}
    case Con{nm, rest}:
      Read.name.if(U32.is_eq(num, idx), nm, _u => Read.name(rest, num, U32.inc(idx)))

# the line of a failed read of the shard named nm
def Read.failure(nm: Name, inst: String, why: String) -> String:
  match nm:
    case Name{source, n}:
      String.concat(["failed ", source, " shard ", U32.show(n), " at ", inst, ": ", why, "\n"])

# one line per failed read: its shard's source and own number, its
# instance and why
def Read.failures(rs: List<&2, Read>, +names: List<&2, Name>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{r, rest}:
      match r:
        case Read{shard, inst, _labels, _ok, why, _pn, _pm, _cn, _ms}:
          Read.failure(Read.name(names, shard, 1), inst, why) ++ Read.failures(rest, names)

# the footer of a run: the shards read and failed, each failed shard named
# by its source and own number with its instance and reason, the unknown
# labels and the wall time
def Read.footer(+rs: List<&2, Read>, names: List<&2, Name>, unknown: U32, ms: Nat) -> String:
  +bad = Read.failed(rs)
  String.concat(["shards: ", Nat.show(List.length(&2, Read, rs)), " read, ",
    Nat.show(List.length(&2, Read, bad)), " failed\n", Read.failures(bad, names),
    "unknown labels: ", U32.show(unknown), "\n",
    "wall time: ", Read.secs(ms), " s"])

# --- files and JSON ---

# a source's run file: its name with every / as _, then .md
def Read.file(src: String) -> String:
  String.join(String.split(src, '/'), "_") ++ ".md"

# the distinct sources of excerpts, sorted
def Read.sources(xs: List<&2, E.Ex>, ys: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      ys
    case Con{x, rest}:
      Read.sources(rest, S.Shard.insert(ys, E.Excerpt.source(E.Excerpt.rec(x))))

# x ahead of rest when it is of the source
def Read.of_source.if(hit: Bool, ex: E.Ex, rest: List<&2, E.Ex>) -> List<&2, E.Ex>:
  match hit:
    case True{}:
      ex <> rest
    case False{}:
      rest

# the excerpts of one source, in order
def Read.of_source(+src: String, xs: List<&2, E.Ex>) -> List<&2, E.Ex>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Read.of_source.if(String.eq(E.Excerpt.source(E.Excerpt.rec(x)), src), x,
        Read.of_source(src, rest))

# the ts of the last excerpt, or dflt
def Read.last_ts(xs: List<&2, E.Ex>, dflt: String) -> String:
  match xs:
    case Nil{}:
      dflt
    case Con{x, rest}:
      Read.last_ts(rest, E.Excerpt.ts(E.Excerpt.rec(x)))

# a source's INDEX.md line: its file, its excerpt count, its first and
# last ts
def Read.index.line(+src: String, +xs: List<&2, E.Ex>) -> String:
  +first = Read.last_ts(List.take(&2, E.Ex, xs, 1n), "")
  String.concat([Read.file(src), " ", src, " ",
    Nat.show(List.length(&2, E.Ex, xs)), " ", first, " ", Read.last_ts(xs, first), "\n"])

# INDEX.md: one line per source
def Read.index(srcs: List<&2, String>, +xs: List<&2, E.Ex>) -> String:
  match srcs:
    case Nil{}:
      ""
    case Con{+src, rest}:
      Read.index.line(src, Read.of_source(src, xs)) ++ Read.index(rest, xs)

# a U32 as a JSON number
def Read.u32(num: U32) -> Value.Json:
  Json.num(U32.show(num))

# strings as JSON strings
def Read.strs.json(xs: List<&2, String>) -> List<&2, Value.Json>:
  match xs:
    case Nil{}:
      []
    case Con{x, rest}:
      Json.str(x) <> Read.strs.json(rest)

# a name's source
def Read.name.source(nm: Name) -> String:
  match nm:
    case Name{source, _n}:
      source

# a name's number
def Read.name.n(nm: Name) -> U32:
  match nm:
    case Name{_source, n}:
      n

# a read as JSON: its run's shard number, then that shard's source and own
# number
def Read.to_json(rd: Read, +names: List<&2, Name>) -> Value.Json:
  match rd:
    case Read{+shard, inst, labels, ok, why, prompt_n, prompt_ms, cache_n, ms}:
      Json.obj([("shard", Read.u32(shard)),
        ("source", Json.str(Read.name.source(Read.name(names, shard, 1)))),
        ("n", Read.u32(Read.name.n(Read.name(names, shard, 1)))), ("inst", Json.str(inst)),
        ("labels", Json.arr(Read.strs.json(labels))),
        ("ok", Json.bool(ok)), ("why", Json.str(why)),
        ("prompt_n", Read.u32(prompt_n)), ("prompt_ms", Read.u32(prompt_ms)),
        ("cache_n", Read.u32(cache_n)), ("ms", Read.u32(ms))])

# an excerpt as JSON: its record's id, source, ts and author, and its
# paragraphs as [n, start, end, text]
def Read.ex_json(ex: E.Ex) -> Value.Json:
  match ex:
    case E.Ex{rec, paras}:
      match rec:
        case R.Record{id, ts, source, author, _thread, _parent, _rps, _ptr}:
          Json.obj([("id", Json.str(id)), ("source", Json.str(source)),
            ("ts", Json.str(ts)), ("author", Json.str(author)),
            ("paras", Json.arr(R.Record.paras(paras)))])

# excerpts as JSON
def Read.exs.json(xs: List<&2, E.Ex>) -> List<&2, Value.Json>:
  match xs:
    case Nil{}:
      []
    case Con{x, rest}:
      Read.ex_json(x) <> Read.exs.json(rest)

# reads as JSON
def Read.reads.json(rs: List<&2, Read>, +names: List<&2, Name>) -> List<&2, Value.Json>:
  match rs:
    case Nil{}:
      []
    case Con{r, rest}:
      Read.to_json(r, names) <> Read.reads.json(rest, names)

# a run as one JSON object: its excerpts and its reads
def Read.report(xs: List<&2, E.Ex>, rs: List<&2, Read>, names: List<&2, Name>) -> String:
  Json.print(Json.obj([
    ("excerpts", Json.arr(Read.exs.json(xs))),
    ("reads", Json.arr(Read.reads.json(rs, names)))]))
