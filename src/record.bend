# episteme/src/record: a record, the unit the log stores and the shards
# pack, and its JSON line. Pure: no IO.
import Base
import ./para.bend as P
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# one record: its id, its ISO 8601 UTC timestamp (`YYYY-MM-DDTHH:MM:SS.mmmZ`,
# so string order is time order), its source, its author, the thread and
# parent record it answers (empty for none), its body as numbered
# paragraphs, and the pointer to a large body (`file:<path>:<line>` or
# `git:<repo path>@<hash>`, empty for none); a pointer record's body is one
# line saying what it points at, its size and its type
type Record is Data:
  Record{id: String, ts: String, source: String, author: String,
    thread: String, parent: String, paras: List<&2, P.Para>, ptr: String}

# the record of the fields with the paragraphs paras, or None when there
# are none
def Record.make.go(
  id: String,
  ts: String,
  source: String,
  author: String,
  thread: String,
  parent: String,
  paras: List<&2, P.Para>,
  ptr: String
) -> Maybe<&2, Record>:
  match paras:
    case Nil{}:
      None{}
    case Con{pa, rest}:
      Some{Record{id, ts, source, author, thread, parent, pa <> rest, ptr}}

# the record of the fields with the body split into paragraphs, or None
# when the body has none
def Record.make(
  id: String,
  ts: String,
  source: String,
  author: String,
  thread: String,
  parent: String,
  body: String,
  ptr: String
) -> Maybe<&2, Record>:
  Record.make.go(id, ts, source, author, thread, parent, P.Para.split(body),
    ptr)

# a U32 as a JSON number
def Record.u32(num: U32) -> Value.Json:
  Json.num(U32.show(num))

# a paragraph as the JSON array [n, start, end, text]
def Record.para(pa: P.Para) -> Value.Json:
  match pa:
    case P.Para{n, start, end, text}:
      Json.arr([Record.u32(n), Record.u32(start), Record.u32(end),
        Json.str(text)])

# paragraphs as JSON arrays, in order
def Record.paras(ps: List<&2, P.Para>) -> List<&2, Value.Json>:
  match ps:
    case Nil{}:
      []
    case Con{pa, rest}:
      Record.para(pa) <> Record.paras(rest)

# a record as a JSON object
def Record.to_json(rec: Record) -> Value.Json:
  match rec:
    case Record{id, ts, source, author, thread, parent, paras, ptr}:
      Json.obj([("id", Json.str(id)), ("ts", Json.str(ts)),
        ("source", Json.str(source)), ("author", Json.str(author)),
        ("thread", Json.str(thread)), ("parent", Json.str(parent)),
        ("paras", Json.arr(Record.paras(paras))), ("ptr", Json.str(ptr))])

# a record as one compact JSON object, with no newline
def Record.to_line(rec: Record) -> String:
  Json.print(Record.to_json(rec))

# the paragraph of the four parts read from [n, start, end, text], or None
# when one is missing or the array does not have exactly four elements
def Record.para.of.go(
  four: Bool,
  num: Maybe<&2, U32>,
  start: Maybe<&2, U32>,
  end: Maybe<&2, U32>,
  text: Maybe<&2, String>
) -> Maybe<&2, P.Para>:
  match four num start end text:
    case True{} Some{a} Some{b} Some{c} Some{d}:
      Some{P.Para{a, b, c, d}}
    case _ _ _ _ _:
      None{}

# a paragraph read from the JSON array [n, start, end, text], or None when
# it is not one
def Record.para.of(+js: Value.Json) -> Maybe<&2, P.Para>:
  Record.para.of.go(Bool.and(Json.is_arr(js), U32.is_eq(Json.len(js), 4)),
    Json.as_u32(Json.at(js, 0)), Json.as_u32(Json.at(js, 1)),
    Json.as_u32(Json.at(js, 2)), Json.as_str(Json.at(js, 3)))

# the paragraph pa ahead of the paragraphs ps, or None when either is
# missing
def Record.paras.cons(
  pa: Maybe<&2, P.Para>,
  ps: Maybe<&2, List<&2, P.Para>>
) -> Maybe<&2, List<&2, P.Para>>:
  match pa ps:
    case Some{x} Some{xs}:
      Some{x <> xs}
    case _ _:
      None{}

# paragraphs read from JSON arrays, in order, or None when one is not a
# paragraph
def Record.paras.of(js: List<&2, Value.Json>) -> Maybe<&2, List<&2, P.Para>>:
  match js:
    case Nil{}:
      Some{[]}
    case Con{head, rest}:
      Record.paras.cons(Record.para.of(head), Record.paras.of(rest))

# paragraphs read from an array of JSON arrays, in order, or None when it
# is empty or not an array (items gives [] for anything else) or one
# element is not a paragraph
def Record.paras.of_some(
  js: List<&2, Value.Json>
) -> Maybe<&2, List<&2, P.Para>>:
  match js:
    case Nil{}:
      None{}
    case Con{head, rest}:
      Record.paras.of(head <> rest)

# an object's string at key, or None when it is missing or not a string
def Record.str(+js: Value.Json, key: String) -> Maybe<&2, String>:
  Json.as_str(Json.get(js, key))

# a string read, or None when it was missing or is empty
def Record.full.go(got: Maybe<&2, String>) -> Maybe<&2, String>:
  match got:
    case None{}:
      None{}
    case Some{str}:
      match str:
        case SNil{}:
          None{}
        case SCon{head, tail}:
          Some{SCon{head, tail}}

# an object's string at key, or None when it is missing, not a string or
# empty
def Record.full(+js: Value.Json, key: String) -> Maybe<&2, String>:
  Record.full.go(Record.str(js, key))

# the record of the parts read from a line, or None when one is missing
def Record.of.go(
  id: Maybe<&2, String>,
  ts: Maybe<&2, String>,
  source: Maybe<&2, String>,
  author: Maybe<&2, String>,
  thread: Maybe<&2, String>,
  parent: Maybe<&2, String>,
  paras: Maybe<&2, List<&2, P.Para>>,
  ptr: Maybe<&2, String>
) -> Maybe<&2, Record>:
  match id ts source author thread parent paras ptr:
    case Some{a} Some{b} Some{c} Some{d} Some{e} Some{f} Some{g} Some{h}:
      Some{Record{a, b, c, d, e, f, g, h}}
    case _ _ _ _ _ _ _ _:
      None{}

# a record read from a parsed JSON object: None unless id, ts and source
# are non-empty strings, author, thread, parent and ptr are strings, and
# paras is a non-empty array of paragraphs
def Record.of_json(+js: Value.Json) -> Maybe<&2, Record>:
  Record.of.go(Record.full(js, "id"), Record.full(js, "ts"),
    Record.full(js, "source"), Record.str(js, "author"),
    Record.str(js, "thread"), Record.str(js, "parent"),
    Record.paras.of_some(Json.items(Json.get(js, "paras"))),
    Record.str(js, "ptr"))

# a record read from a parsed JSON line, or None when there is none
def Record.of_parsed(parsed: Maybe<&2, Value.Json>) -> Maybe<&2, Record>:
  match parsed:
    case None{}:
      None{}
    case Some{js}:
      Record.of_json(js)

# a record read from its JSON line, or None when the line is not one
def Record.of_line(line: String) -> Maybe<&2, Record>:
  Record.of_parsed(Json.parse(line))

# the line a reader sees above a record's paragraphs:
# "== <source> | <ts> | <author> | <id>"
def Record.header(rec: Record) -> String:
  match rec:
    case Record{id, ts, source, author, _thread, _parent, _paras, _ptr}:
      String.concat(["== ", source, " | ", ts, " | ", author, " | ", id])

# the code points of the paragraph texts of ps
def Record.texts(ps: List<&2, P.Para>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          Nat.add(String.length(text), Record.texts(rest))

# a record's size in code points: its header and its paragraph texts
def Record.size(+rec: Record) -> Nat:
  match rec:
    case Record{_id, _ts, _source, _author, _thread, _parent, paras, _ptr}:
      Nat.add(String.length(Record.header(rec)), Record.texts(paras))

# a record's size in code points, as a U32
def Record.chars(+rec: Record) -> U32:
  U32.from_nat(Record.size(rec))

# a paragraph moved by code points on: its start and end plus by
def Record.shift.para(pa: P.Para, +by: U32) -> P.Para:
  match pa:
    case P.Para{n, start, end, text}:
      P.Para{n, U32.add(start, by), U32.add(end, by), text}

# paragraphs moved by code points on, in order
def Record.shift.paras(ps: List<&2, P.Para>, +by: U32) -> List<&2, P.Para>:
  match ps:
    case Nil{}:
      []
    case Con{pa, rest}:
      Record.shift.para(pa, by) <> Record.shift.paras(rest, by)

# a record whose body was cut from a text at offset by, its paragraphs'
# offsets moved to be offsets into that whole text
def Record.shift(rec: Record, +by: U32) -> Record:
  match rec:
    case Record{id, ts, source, author, thread, parent, paras, ptr}:
      Record{id, ts, source, author, thread, parent,
        Record.shift.paras(paras, by), ptr}

# True when a string is not empty
def Record.filled(str: String) -> Bool:
  match str:
    case SNil{}:
      False{}
    case SCon{_head, _tail}:
      True{}

# True when ingest may append a record: its id, ts and source are not
# empty, as Record.of_line asks, and its header line is at most
# Para.max() code points, as shard sizes assume
def Record.fits(+rec: Record) -> Bool:
  match rec:
    case Record{id, ts, source, _author, _thread, _parent, _paras, _ptr}:
      Bool.and(Record.filled(id), Bool.and(Record.filled(ts),
        Bool.and(Record.filled(source),
          Nat.is_le(String.length(Record.header(rec)),
            U32.to_nat(P.Para.max())))))

# rec ahead of rest when keep
def Record.fitting.put(keep: Bool, rec: Record, rest: List<&2, Record>) -> List<&2, Record>:
  match keep:
    case True{}:
      rec <> rest
    case False{}:
      rest

# the records of recs ingest appends, in order: those Record.fits passes
def Record.fitting(recs: List<&2, Record>) -> List<&2, Record>:
  match recs:
    case Nil{}:
      []
    case Con{+rec, rest}:
      Record.fitting.put(Record.fits(rec), rec, Record.fitting(rest))
