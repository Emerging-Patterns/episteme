# episteme/src/intake: what `episteme ingest records` makes of records a
# caller gives as JSON lines, each one record as the log stores it
# (Record.to_json), with `text` allowed in place of `paras`. Against a
# source's current records, read from its shards: a record identical to
# the current one with its id gives nothing; one with an id no current
# record has is appended; one that differs from the current one is appended
# after a removal of its id, so it becomes the current version and its
# source is packed again. With `--complete` the input is the whole of each
# source it names, and every current record of such a source whose id the
# input lacks is removed (src/live.bend). Pure: no IO.
import Base
import ./para.bend as P
import ./record.bend as R
import ./live.bend as L
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# --- one line ---

# an optional string field: "" when it is missing, None when it is no string
def Intake.opt(+js: Value.Json, +key: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Json.has(js, key), Json.as_str(Json.get(js, key)), Some{""})

# paragraphs, or None when there are none
def Intake.some(ps: List<&2, P.Para>) -> Maybe<&2, List<&2, P.Para>>:
  match ps:
    case Nil{}:
      None{}
    case Con{pa, rest}:
      Some{pa <> rest}

# the paragraphs of a text, or None when it has none
def Intake.split(got: Maybe<&2, String>) -> Maybe<&2, List<&2, P.Para>>:
  match got:
    case None{}:
      None{}
    case Some{+text}:
      Intake.some(P.Para.split(text))

# the paragraphs of a line by which of `paras` and `text` it has
def Intake.body.of(paras: Bool, text: Bool, +js: Value.Json) -> Maybe<&2, List<&2, P.Para>>:
  match paras text:
    case True{} False{}:
      R.Record.paras.of_some(Json.items(Json.get(js, "paras")))
    case False{} True{}:
      Intake.split(Json.as_str(Json.get(js, "text")))
    case _ _:
      None{}

# the paragraphs of a line: its `paras` as stored, or its `text` split into
# paragraphs; None when it has both, neither, or no paragraph
def Intake.body(+js: Value.Json) -> Maybe<&2, List<&2, P.Para>>:
  Intake.body.of(Json.has(js, "paras"), Json.has(js, "text"), js)

# True when a record can be taken: it fits the log (Record.fits), its ts
# has the form YYYY-MM-DDTHH:MM:SS.mmmZ (24 code points ending Z) and it is
# no removal
def Intake.ok(+rec: R.Record) -> Bool:
  match rec:
    case R.Record{_id, +ts, _source, _author, _thread, _parent, _paras, _ptr}:
      Bool.and(R.Record.fits(rec), Bool.and(Bool.and(Nat.is_eq(String.length(ts), 24n),
        String.ends_with(ts, "Z")), Bool.not(L.Live.gone(rec))))

# the record when it can be taken, else None
def Intake.keep(got: Maybe<&2, R.Record>) -> Maybe<&2, R.Record>:
  match got:
    case None{}:
      None{}
    case Some{+rec}:
      Bool.pick(Maybe<&2, R.Record>, Intake.ok(rec), Some{rec}, None{})

# the record of a parsed line, or None when it is no object or a field is
# missing or of the wrong kind
def Intake.of(got: Maybe<&2, Value.Json>) -> Maybe<&2, R.Record>:
  match got:
    case None{}:
      None{}
    case Some{+js}:
      Intake.keep(R.Record.of.go(R.Record.full(js, "id"), R.Record.full(js, "ts"),
        R.Record.full(js, "source"), Intake.opt(js, "author"), Intake.opt(js, "thread"),
        Intake.opt(js, "parent"), Intake.body(js), Intake.opt(js, "ptr")))

# the record of one input line, or None when it is none
def Intake.line(text: String) -> Maybe<&2, R.Record>:
  Intake.of(Json.parse(text))

# rec ahead of the records of the rest, or the rest's failure
def Intake.cons(rec: R.Record, got: Result<&2, &2, U32, List<&2, R.Record>>) -> Result<&2, &2, U32, List<&2, R.Record>>:
  match got:
    case Fail{bad}:
      Fail{bad}
    case Done{recs}:
      Done{rec <> recs}

# the records of the rest after the record of a line, or the number of the
# first line that is no record
def Intake.lines.if(
  got: Maybe<&2, R.Record>,
  +num: U32,
  rest: Unit -> Result<&2, &2, U32, List<&2, R.Record>>
) -> Result<&2, &2, U32, List<&2, R.Record>>:
  match got:
    case None{}:
      Fail{num}
    case Some{rec}:
      Intake.cons(rec, rest(Unit{}))

# the records of input lines numbered from num, an empty line skipped, or
# the number of the first line that is no record
def Intake.lines(ls: List<&2, String>, +num: U32) -> Result<&2, &2, U32, List<&2, R.Record>>:
  match ls:
    case Nil{}:
      Done{[]}
    case Con{SNil{}, rest}:
      Intake.lines(rest, U32.inc(num))
    case Con{SCon{h, t}, rest}:
      Intake.lines.if(Intake.line(SCon{h, t}), num, _u => Intake.lines(rest, U32.inc(num)))

# --- sources ---

# True when text is one of xs
def Intake.mem(+text: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      Bool.or(String.eq(x, text), Intake.mem(text, rest))

# a record's source
def Intake.source(rec: R.Record) -> String:
  match rec:
    case R.Record{_id, _ts, source, _author, _thread, _parent, _paras, _ptr}:
      source

# x ahead of rest when keep, else rest
def Intake.put(keep: Bool, x: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match keep:
    case True{}:
      x <> rest
    case False{}:
      rest

# the records of xs of the source, in order
def Intake.of_source(+src: String, xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Intake.put(String.eq(Intake.source(x), src), x, Intake.of_source(src, rest))

# the sources of records after src, src first unless it was seen
def Intake.sources.if(
  seen: Bool,
  src: String,
  rest: Unit -> List<&2, String>,
  more: Unit -> List<&2, String>
) -> List<&2, String>:
  match seen:
    case True{}:
      rest(Unit{})
    case False{}:
      src <> more(Unit{})

# the sources of records, each once, in the order they first come
def Intake.sources(xs: List<&2, R.Record>, +seen: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, +rest}:
      +src = Intake.source(x)
      Intake.sources.if(Intake.mem(src, seen), src, _u => Intake.sources(rest, seen),
        _u => Intake.sources(rest, src <> seen))

# the records of xs whose id no later record of xs has: the last of each
# id, in order
def Intake.last(xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match xs:
    case Nil{}:
      []
    case Con{+x, +rest}:
      Intake.put(Bool.not(L.Live.has(L.Live.id(x), rest)), x, Intake.last(rest))

# --- the plan ---

# the removal of a record's id: its id, ts and source, one paragraph
# "(removed)" and the pointer "removed"
def Intake.removal(rec: R.Record) -> R.Record:
  match rec:
    case R.Record{id, ts, source, _author, _thread, _parent, _paras, _ptr}:
      R.Record{id, ts, source, "", "", "", [P.Para{1, 0, 0, "(removed)"}], L.Live.removed()}

# True when two records are the same in every field
def Intake.same(a: R.Record, b: R.Record) -> Bool:
  String.eq(R.Record.to_line(a), R.Record.to_line(b))

# nothing more for a record the same as the current one, else its id's
# removal and then the record
def Intake.changed(same: Bool, +x: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match same:
    case True{}:
      rest
    case False{}:
      Intake.removal(x) <> x <> rest

# what a record gives against the current record with its id, if any
def Intake.vs(cur: Maybe<&2, R.Record>, +x: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match cur:
    case None{}:
      x <> rest
    case Some{h}:
      Intake.changed(Intake.same(h, x), x, rest)

# what one record gives against the current records held, then rest
def Intake.one(+held: List<&2, R.Record>, +x: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  Intake.vs(L.Live.pick(L.Live.id(x), held), x, rest)

# what the records give against the current records held, in order
def Intake.ones(+held: List<&2, R.Record>, xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Intake.one(held, x, Intake.ones(held, rest))

# the removal of a current record ahead of rest when the input lacks its id
def Intake.lacks.if(lacks: Bool, rec: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match lacks:
    case True{}:
      Intake.removal(rec) <> rest
    case False{}:
      rest

# the removals of the current records whose id no record of xs has, in order
def Intake.lacks(held: List<&2, R.Record>, +xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match held:
    case Nil{}:
      []
    case Con{+h, rest}:
      Intake.lacks.if(Bool.not(L.Live.has(L.Live.id(h), xs)), h, Intake.lacks(rest, xs))

# what a run appends for one source: each input record's, then, when the
# input is the whole source, the removals of the current records it lacks
def Intake.plan(complete: Bool, +held: List<&2, R.Record>, +xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match complete:
    case True{}:
      List.append(&2, R.Record, Intake.ones(held, xs), Intake.lacks(held, xs))
    case False{}:
      Intake.ones(held, xs)
