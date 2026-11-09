# `Read.request(slot, s, q)` is exactly: messages system `Read.prompt()`, user
# `Shard.render(s)`, user `Question: <q>`, in that order; `temperature` 0,
# `max_tokens` 6 per paragraph of `s` (its count of `Shard.labels`) plus 576
# (64 for the answer, 512 for the reader's capped thinking),
# `cache_prompt` true, `id_slot` slot, `chat_template_kwargs`
# `{"enable_thinking": false}`, and `response_format` the JSON schema
# `{"type": "object", "properties": {"ids": {"type": "array", "items":
# {"enum": ["p1", ..., "pK"]}, "maxItems": K}}, "required": ["ids"]}`, K the
# paragraphs of `s`, so the grammar admits only the shard's own labels.
#
# `src/read.bend` decides what a reader is asked, what its reply means and
# what `ask` reports. A read is `Read{shard, inst, labels, ok, why, prompt_n,
# prompt_ms, cache_n, ms}`: the shard's number in the run, the instance's URL,
# the labels the reader named, whether the call answered, why it failed, and
# the server's `timings` in whole units (`ms` is `prompt_ms` plus
# `predicted_ms`). `Read.request(slot, s, q)` is the body of `POST
# <url>/v1/chat/completions`: the system prompt `Read.prompt()`, then the
# shard as `Shard.render` writes it, then `Question: <q>`, so the shard is a
# prefix every question shares; a closed example prints the schema of a
# three-paragraph shard. `Read.content(js)` is the string at
# `choices[0].message.content` and `Read.answer(c)` reads it as JSON whose
# `ids` is an array of strings; closed examples check a reply naming two
# labels with its timings, an empty answer, content cut short at `max_tokens`,
# a 400 with a good body, ids that are numbers and a body that is not JSON.
# `Read.ordered(ss, rs)` pairs the shards with the pool's reads: for each
# shard, in order, the first read of its number in `rs`, or `Read.fail(n, "",
# "no read")` when there is none; a closed example checks both.
# `Read.failed(rs)` is what the footer lists and `Read.code(rs)` is the run's
# exit code. `Read.footer(rs, names, unknown, ms)` writes `shards: <n> read,
# <k> failed`, one line `failed <source> shard <n> at <inst>: <why>` per
# failed read, `<source>` and `<n>` the failed shard's own name
# `Read.Name{source, n}` (the run's shard `k` is named by `names[k - 1]`),
# `unknown labels: <u>` and `wall time: <s> s`; a closed example checks it.
# `Read.fits(chars, budget, per)` says whether the rendered excerpts are
# printed or written to run files.
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# the reader's system prompt, word for word
def reader_prompt() -> String:
  "You read one slice of a record and find every paragraph that could help answer a question. Each paragraph starts with a label in square brackets, like [p12]. Return the labels of every paragraph that is plausibly related to the question: direct answers, definitions, background, examples, and anything mentioning the same people, terms or events. When unsure, include it. If nothing is related, return an empty list. Return only labels that appear in the text."

# a chat message
def chat_message(role: String, content: String) -> Value.Json:
  Json.obj([("role", Json.str(role)), ("content", Json.str(content))])

# the labels p<idx> on, cnt of them, as JSON strings
def label_enum(cnt: Nat, +idx: U32) -> List<&2, Value.Json>:
  match cnt:
    case 0n:
      []
    case 1n+more:
      Json.str("p" ++ U32.show(idx)) <> label_enum(more, U32.inc(idx))

# the response format for cnt paragraphs: an object whose ids is an array
# of at most cnt items, each one of p1 to p<cnt>
def ids_format(+cnt: Nat) -> Value.Json:
  Json.obj([("type", Json.str("json_schema")),
    ("json_schema", Json.obj([("schema", Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("ids", Json.obj([
        ("type", Json.str("array")),
        ("items", Json.obj([("enum", Json.arr(label_enum(cnt, 1)))])),
        ("maxItems", Json.num(Nat.show(cnt)))]))])),
      ("required", Json.arr([Json.str("ids")]))]))]))])

# how many paragraphs a shard holds: one label each
def shard_paras(sh: S.Shard) -> Nat:
  List.length(&2, S.Shard.Label(), S.Shard.labels(sh))

# the chat completions body for a shard and a question on a slot: the
# prompt, the shard, the question, in that order, at temperature 0, with
# room for 6 tokens a paragraph, 64 more and 512 of thinking
def chat_request(slot: U32, +sh: S.Shard, question: String) -> Value.Json:
  Json.obj([("messages", Json.arr([chat_message("system", reader_prompt()),
      chat_message("user", S.Shard.render(sh)),
      chat_message("user", "Question: " ++ question)])),
    ("temperature", Json.num("0")),
    ("max_tokens", Json.num(U32.show(U32.add(U32.mul(6, U32.from_nat(shard_paras(sh))), 576)))),
    ("cache_prompt", Json.bool(True{})),
    ("id_slot", Json.num(U32.show(slot))),
    ("chat_template_kwargs", Json.obj([("enable_thinking", Json.bool(False{}))])),
    ("response_format", ids_format(shard_paras(sh)))])

# LAW: a reader is asked with exactly this body
law request_body:
  for slot: U32
  for s: S.Shard
  for question: String
  {Rd.Read.request(slot, s, question) == chat_request(slot, s, question)
    : Value.Json}
