# episteme/src/gold: a canon gold question set as questions.jsonl lines,
# each gold chunk id looked up in the canon index. IO: the YAML is read with
# yaml-for-bend and the chunks table with bend-kit-sqlite.
#
# Trusted, not proved: `episteme eval-import <canon dir> <questions.yaml>
# <corpus>` reads the file with yaml-for-bend's `load` (the YAML 1.2 Core
# schema) and takes, in order, each entry of its `questions`: its `id`, its
# `question`, its `answer` or else its `reference` (`""` when it has neither),
# and its gold chunk ids, the strings of its `gold` or else the `chunk` of
# each of its `locators`, each id once in first-seen order (a repeated id is
# one gold span). It stops with exit 1 when `<canon dir>` does not list
# `index.sqlite`, so a wrong directory never makes an empty database; else it
# looks each chunk id up in `<canon dir>/index.sqlite` with bend-kit-sqlite
# (`select source_id, start, end, text from chunks where id = ?1`), and prints
# one line per question, `{"id", "question", "filter": ["book:<corpus>/"],
# "gold": [{"source": "book:<corpus>/<source_id>", "start", "end"}...],
# "answer"}`, the offsets the chunk's own, code-point offsets into `<canon
# dir>/text/<source_id>.txt` as the books connector's are
# (src/conn/books.bend). It prints nothing and exits 1 when the file is not
# such YAML, an entry lacks an id, a question or a gold chunk, a chunk id is
# not in the table, or the first gold span of the first question does not
# slice its book file to the chunk's `text`.
#
# Why it is trusted: It reads YAML through yaml-for-bend and the chunks table
# through bend-kit-sqlite, which loads libsqlite3 at run time
# (`BEND_LIBSQLITE` names it); no law reaches either. The text check on the
# first gold span stops a run whose offsets are not code-point offsets.
import Base
import ./store.bend as St
import 0x8abe7473e8854cc69c687ee77b7d72e3/main.bend as Sys
import 0x856d414a32087762da315b6efc605eaa/yaml.bend as Y
import 0x856d414a32087762da315b6efc605eaa/value.bend as V
import 0x856d414a32087762da315b6efc605eaa/token.bend as T
import 0x1dd647736fb09289bc1eed9825ef1113/sqlite.bend as Sql
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# a canon question: its id, its text, its answer and its gold chunk ids
type Q is Data:
  Q{id: String, question: String, answer: String, chunks: List<&2, String>}

# a row of the chunks table: its book, its code-point offsets and its text
type Chunk is Data:
  Chunk{source: String, start: U32, end: U32, text: String}

# --- the YAML ---

# a scalar's text: a string's, or an integer's or float's spelling
def Gold.scalar(val: V.Yaml) -> Maybe<&2, String>:
  match val:
    case V.Str{t}:
      Some{t}
    case V.Int{t}:
      Some{t}
    case V.Float{t}:
      Some{t}
    case _:
      None{}

# a text ahead of more, or None when either is missing
def Gold.cons(got: Maybe<&2, String>, more: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match got more:
    case Some{x} Some{xs}:
      Some{x <> xs}
    case _ _:
      None{}

# the texts of scalars, or None when one is not a scalar
def Gold.texts(vs: List<&2, V.Yaml>) -> Maybe<&2, List<&2, String>>:
  match vs:
    case Nil{}:
      Some{[]}
    case Con{v, rest}:
      Gold.cons(Gold.scalar(v), Gold.texts(rest))

# the chunk of each locator, or None when one has none
def Gold.locators(ls: List<&2, V.Yaml>) -> Maybe<&2, List<&2, String>>:
  match ls:
    case Nil{}:
      Some{[]}
    case Con{l, rest}:
      Gold.cons(Gold.scalar(V.at(l, "chunk")), Gold.locators(rest))

# id ahead of the rest unless seen
def Gold.uniq.if(seen: Bool, id: String, rest: List<&2, String>) -> List<&2, String>:
  match seen:
    case True{}:
      rest
    case False{}:
      id <> rest

# True when text is one of xs
def Gold.has(+text: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{head, rest}:
      List.any.if(_u => Gold.has(text, rest), String.eq(text, head))

# the ids not in seen, each once, in first-seen order
def Gold.uniq(ids: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match ids:
    case Nil{}:
      []
    case Con{+id, rest}:
      Gold.uniq.if(Gold.has(id, seen), id, Gold.uniq(rest, id <> seen))

# a non-empty list with each id once, in first-seen order, or None
def Gold.some(got: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match got:
    case Some{Con{x, rest}}:
      Some{Gold.uniq(x <> rest, [])}
    case _:
      None{}

# the gold chunk ids: those of gold when it has some, else the locators'
def Gold.ids.of(gold: V.Yaml, +entry: V.Yaml) -> Maybe<&2, List<&2, String>>:
  match gold:
    case V.Seq{xs}:
      Gold.some(Gold.texts(xs))
    case _:
      Gold.some(Gold.locators(V.items(V.at(entry, "locators"))))

# the answer, else the reference, else ""
def Gold.answer(got: Maybe<&2, String>, +entry: V.Yaml) -> String:
  match got:
    case Some{a}:
      a
    case None{}:
      Maybe.default(&2, String, Gold.scalar(V.at(entry, "reference")), "")

# a question when its id, its text and its chunk ids are there
def Gold.q.of(
  id: Maybe<&2, String>,
  question: Maybe<&2, String>,
  answer: String,
  chunks: Maybe<&2, List<&2, String>>
) -> Maybe<&2, Q>:
  match id question chunks:
    case Some{i} Some{t} Some{cs}:
      Some{Q{i, t, answer, cs}}
    case _ _ _:
      None{}

# an entry of questions as a Q, or None
def Gold.q(+entry: V.Yaml) -> Maybe<&2, Q>:
  Gold.q.of(Gold.scalar(V.at(entry, "id")), Gold.scalar(V.at(entry, "question")),
    Gold.answer(Gold.scalar(V.at(entry, "answer")), entry), Gold.ids.of(V.at(entry, "gold"), entry))

# a question ahead of more, or None when either is missing
def Gold.qs.cons(got: Maybe<&2, Q>, more: Maybe<&2, List<&2, Q>>) -> Maybe<&2, List<&2, Q>>:
  match got more:
    case Some{x} Some{xs}:
      Some{x <> xs}
    case _ _:
      None{}

# every entry as a Q, or None when one is not one
def Gold.qs(vs: List<&2, V.Yaml>) -> Maybe<&2, List<&2, Q>>:
  match vs:
    case Nil{}:
      Some{[]}
    case Con{v, rest}:
      Gold.qs.cons(Gold.q(v), Gold.qs(rest))

# a value, or stop with msg
def Gold.must(-A: Data, got: Maybe<&2, A>, msg: String) -> IO(A):
  match got:
    case None{}:
      St.Store.die(A, msg)
    case Some{val}:
      IO.pure(A, val)

# the questions of a loaded file, or stop
def Gold.loaded(got: Result<&2, &2, T.Error, V.Yaml>, +path: String) -> IO(List<&2, Q>):
  match got:
    case Fail{e}:
      St.Store.die(List<&2, Q>, path ++ ": " ++ T.error.show(e))
    case Done{doc}:
      Gold.must(List<&2, Q>, Gold.qs(V.items(V.at(doc, "questions"))),
        path ++ ": an entry of questions lacks an id, a question or a gold chunk")

# --- the chunks table ---

# a sqlite answer, or stop naming what failed
def Gold.ok(-A: Data, res: Result<&1, &1, U32 & String, A>, what: String) -> IO(A):
  match res:
    case Fail{(code, msg)}:
      St.Store.die(A, "sqlite " ++ what ++ ": " ++ U32.show(code) ++ " " ++ msg)
    case Done{a}:
      IO.pure(A, a)

# the chunk on the statement's current row
def Gold.columns(+st: U32) -> IO(Chunk):
  do IO<Chunk>:
    r0 : Result<&1, &1, U32 & String, String> <- Sql.stmt.column.text(st, 0)
    source : String <- Gold.ok(String, r0, "source_id")
    r1 : Result<&1, &1, U32 & String, U32> <- Sql.stmt.column.int(st, 1)
    start : U32 <- Gold.ok(U32, r1, "start")
    r2 : Result<&1, &1, U32 & String, U32> <- Sql.stmt.column.int(st, 2)
    end : U32 <- Gold.ok(U32, r2, "end")
    r3 : Result<&1, &1, U32 & String, String> <- Sql.stmt.column.text(st, 3)
    text : String <- Gold.ok(String, r3, "text")
    return Chunk{source, start, end, text}

# the chunk when the step found a row, else stop naming the id
def Gold.found(row: Bool, +st: U32, id: String) -> IO(Chunk):
  match row:
    case True{}:
      Gold.columns(st)
    case False{}:
      St.Store.die(Chunk, "no chunk " ++ id ++ " in the chunks table")

# the chunk with the id, by the prepared statement
def Gold.chunk(+st: U32, +id: String) -> IO(Chunk):
  do IO<Chunk>:
    r0 : Result<&1, &1, U32 & String, Unit> <- Sql.stmt.reset(st)
    _u0 : Unit <- Gold.ok(Unit, r0, "reset")
    r1 : Result<&1, &1, U32 & String, Unit> <- Sql.stmt.bind.text(st, 1, id)
    _u1 : Unit <- Gold.ok(Unit, r1, "bind")
    r2 : Result<&1, &1, U32 & String, Bool> <- Sql.stmt.step(st)
    row : Bool <- Gold.ok(Bool, r2, "step")
    Gold.found(row, st, id)

# the chunks with the ids, in order
def Gold.chunks(+st: U32, ids: List<&2, String>) -> IO(List<&2, Chunk>):
  match ids:
    case Nil{}:
      IO.pure(List<&2, Chunk>, [])
    case Con{id, rest}:
      do IO<List<&2, Chunk>>:
        c : Chunk <- Gold.chunk(st, id)
        cs : List<&2, Chunk> <- Gold.chunks(st, rest)
        return c <> cs

# a question with its gold chunks
type Got is Data:
  Got{q: Q, chunks: List<&2, Chunk>}

# every question with its gold chunks, in order
def Gold.each(+st: U32, qs: List<&2, Q>) -> IO(List<&2, Got>):
  match qs:
    case Nil{}:
      IO.pure(List<&2, Got>, [])
    case Con{q, rest}:
      match q:
        case Q{+id, +question, +answer, +chunks}:
          do IO<List<&2, Got>>:
            cs : List<&2, Chunk> <- Gold.chunks(st, chunks)
            more : List<&2, Got> <- Gold.each(st, rest)
            return Got{Q{id, question, answer, chunks}, cs} <> more

# --- the lines ---

# a chunk as a gold span of book:<corpus>/<source>
def Gold.span(+corpus: String, chunk: Chunk) -> Value.Json:
  match chunk:
    case Chunk{source, start, end, _text}:
      Json.obj([("source", Json.str("book:" ++ corpus ++ "/" ++ source)),
        ("start", Json.num(U32.show(start))), ("end", Json.num(U32.show(end)))])

# chunks as gold spans
def Gold.spans(+corpus: String, cs: List<&2, Chunk>) -> List<&2, Value.Json>:
  match cs:
    case Nil{}:
      []
    case Con{c, rest}:
      Gold.span(corpus, c) <> Gold.spans(corpus, rest)

# a question's line: id, question, the corpus filter, gold spans, answer
def Gold.line(+corpus: String, got: Got) -> String:
  match got:
    case Got{q, cs}:
      match q:
        case Q{id, question, answer, _chunks}:
          Json.print(Json.obj([("id", Json.str(id)), ("question", Json.str(question)),
            ("filter", Json.arr([Json.str("book:" ++ corpus ++ "/")])),
            ("gold", Json.arr(Gold.spans(corpus, cs))), ("answer", Json.str(answer))]))

# every question's line
def Gold.lines(+corpus: String, gs: List<&2, Got>) -> String:
  match gs:
    case Nil{}:
      ""
    case Con{g, rest}:
      Gold.line(corpus, g) ++ "\n" ++ Gold.lines(corpus, rest)

# --- the offset check ---

# nothing when the book's text from start to end is the chunk's, else stop
def Gold.sliced(+book: String, chunk: Chunk, +path: String) -> IO(Unit):
  match chunk:
    case Chunk{_source, +start, +end, +text}:
      St.Store.exited(String.eq(String.take(String.drop(book, U32.to_nat(start)),
        Nat.sub(U32.to_nat(end), U32.to_nat(start))), text),
        path ++ "[" ++ U32.show(start) ++ ":" ++ U32.show(end)
          ++ "] is not the chunk's text: offsets are not code-point offsets")

# check the first gold chunk of the first question against its book file
def Gold.check(+dir: String, gs: List<&2, Got>) -> IO(Unit):
  match gs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{g, _rest}:
      match g:
        case Got{_q, cs}:
          match cs:
            case Nil{}:
              IO.pure(Unit, Unit{})
            case Con{+c, _more}:
              match c:
                case Chunk{+source, start, end, text}:
                  +path = dir ++ "/text/" ++ source ++ ".txt"
                  do IO<Unit>:
                    book : String <- St.Store.read(path)
                    Gold.sliced(book, Chunk{source, start, end, text}, path)

# --- the command ---

# the opened database's questions with their chunks, the statement
# finalized and the database closed
def Gold.lookup(+db: U32, qs: List<&2, Q>) -> IO(List<&2, Got>):
  do IO<List<&2, Got>>:
    r0 : Result<&1, &1, U32 & String, U32> <- Sql.stmt.prepare(db,
      "select source_id, start, end, text from chunks where id = ?1")
    +st : U32 <- Gold.ok(U32, r0, "prepare")
    gs : List<&2, Got> <- Gold.each(st, qs)
    r1 : Result<&1, &1, U32 & String, Unit> <- Sql.stmt.finalize(st)
    _u1 : Unit <- Gold.ok(Unit, r1, "finalize")
    r2 : Result<&1, &1, U32 & String, Unit> <- Sql.db.close(db)
    _u2 : Unit <- Gold.ok(Unit, r2, "close")
    return gs

# nothing when the listing of dir holds index.sqlite, else stop, so a wrong
# directory never makes an empty database
def Gold.there(res: Result<&1, &1, U32 & String, List<&2, String>>, +dir: String) -> IO(Unit):
  match res:
    case Fail{(code, why)}:
      St.Store.die(Unit, Sys.err.os(code, why, dir))
    case Done{names}:
      St.Store.exited(Gold.has("index.sqlite", names), "no index.sqlite in " ++ dir)

# `episteme eval-import <canon dir> <questions.yaml> <corpus>`: print one
# questions.jsonl line per question, or nothing and stop when a question,
# a chunk or the offset check fails
def Gold.run(+dir: String, +path: String, +corpus: String) -> IO(Unit):
  do IO<Unit>:
    text : String <- St.Store.read(path)
    qs : List<&2, Q> <- Gold.loaded(Y.load(text), path)
    listed : Result<&1, &1, U32 & String, List<&2, String>> <- Sys.dir.list(dir)
    Gold.there(listed, dir)
    r0 : Result<&1, &1, U32 & String, U32> <- Sql.db.open(dir ++ "/index.sqlite")
    +db : U32 <- Gold.ok(U32, r0, "open " ++ dir ++ "/index.sqlite")
    +gs : List<&2, Got> <- Gold.lookup(db, qs)
    Gold.check(dir, gs)
    IO.write(Gold.lines(corpus, gs))
