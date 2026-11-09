# episteme/src/conn/books: the books connector. A corpus is the canon
# directory <root>/<corpus>/text/, root $EPISTEME_BOOKS or
# ~/.local/share/canonagents; each <book>.txt there, in name order, is cut
# at the offsets of its <book>.heads.json (every level), or of its
# <book>.pages.json when it has no headings, into one record per span,
# the text before the first cut its own record. IO: the trusted shell.
#
# Trusted, not proved: `episteme ingest books <corpus>...` reads its cursor
# with `Store.cursor("books")` (one `<corpus>/<book>.txt` per line), then the
# books `<root>/<corpus>/text/<book>.txt` in name order, root
# `$EPISTEME_BOOKS` or `~/.local/share/canonagents`, skips each the cursor
# lists, and ingests each other with its own `Ingest.run`, whose batch carries
# the cursor with that book added. A book is cut at the `offset` of every
# entry of `<book>.heads.json`, or, when it has none, at every number of
# `<book>.pages.json`, sorted and each once, keeping those past 0 and inside
# the text. Each span from one cut to the next, the first from 0, is one
# record by `Record.make` (none when it has no paragraph): id
# `book:<corpus>/<book>@<start>`, source `book:<corpus>/<book>`, author
# `<book>`, ts `<year>-01-01T00:00:00.000Z` when the book id ends in exactly
# four digits and the ingest time otherwise, and its paragraphs moved by the
# span's start with `Record.shift`, so their offsets are code-point offsets
# into the whole book file. Spans start at distinct offsets, so ids are
# distinct and never empty, and a book is given once: its records and the
# cursor that lists it are in one batch.
#
# Why it is trusted: It reads canon files and the clock, which no law reaches;
# the paragraph offsets rest on laws/ShiftMovesOffsets.bend. The smoke test
# checks a whole-file offset on the fixture.
import Base
import ../record.bend as R
import ../store.bend as St
import ../ingest.bend as In
import ezsys@0.1.0.0/main.bend as Sys
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# a span of a book: where it starts, in code points, and its text
type Span is Data:
  Span{at: U32, body: String}

# the number of code points of a text, as a U32
def Books.len(str: String, +acc: U32) -> U32:
  match str:
    case SNil{}:
      acc
    case SCon{_head, tail}:
      Books.len(tail, U32.inc(acc))

# the number ahead of rest, when there is one
def Books.opt(got: Maybe<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  match got:
    case None{}:
      rest
    case Some{x}:
      x <> rest

# the numbers of JSON values, those that are U32s, in order
def Books.nums(js: List<&2, Value.Json>) -> List<&2, U32>:
  match js:
    case Nil{}:
      []
    case Con{head, rest}:
      Books.opt(Json.as_u32(head), Books.nums(rest))

# the "offset" of each heading object, in order
def Books.heads(js: List<&2, Value.Json>) -> List<&2, U32>:
  match js:
    case Nil{}:
      []
    case Con{head, rest}:
      Books.opt(Json.as_u32(Json.get(head, "offset")), Books.heads(rest))

# the items of a parsed JSON array, or none
def Books.items(got: Maybe<&2, Value.Json>) -> List<&2, Value.Json>:
  match got:
    case None{}:
      []
    case Some{js}:
      Json.items(js)

# the heading offsets, or the page offsets when there are none
def Books.offsets.if(heads: List<&2, U32>, pages: List<&2, U32>) -> List<&2, U32>:
  match heads:
    case Nil{}:
      pages
    case Con{head, rest}:
      head <> rest

# off ahead of rest when keep
def Books.cuts.if(keep: Bool, off: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}:
      off <> rest
    case False{}:
      rest

# the offsets in ascending order, each once, keeping those inside the text
# past its start, from at on
def Books.cuts.go(xs: List<&2, U32>, +last: U32, +len: U32) -> List<&2, U32>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Books.cuts.if(Bool.and(U32.is_gt(x, last), U32.is_lt(x, len)), x,
        Books.cuts.go(rest, U32.max(x, last), len))

# the offsets a book is cut at, ascending, each once, inside the text and
# past offset 0
def Books.cuts(offs: List<&2, U32>, +len: U32) -> List<&2, U32>:
  Books.cuts.go(List.sort(~U32, ~U32.is_le, offs), 0, len)

# a text starting at offset at, cut at the ascending offsets cuts, as spans
def Books.spans(cuts: List<&2, U32>, +text: String, +at: U32) -> List<&2, Span>:
  match cuts:
    case Nil{}:
      [Span{at, text}]
    case Con{+cut, rest}:
      +size = U32.to_nat(U32.sub(cut, at))
      Span{at, String.take(text, size)}
        <> Books.spans(rest, String.drop(text, size), cut)

# a year's timestamp when four is True
def Books.year.of(four: Bool, digits: String) -> Maybe<&2, String>:
  match four:
    case True{}:
      Some{digits ++ "-01-01T00:00:00.000Z"}
    case False{}:
      None{}

# the four trailing digits of a book id as a year's timestamp, or None
def Books.year.if(+digits: String) -> Maybe<&2, String>:
  Books.year.of(Nat.is_eq(String.length(digits), 4n), digits)

# the run of digits that ends the text read so far, after one more char
def Books.trail.next(digit: Bool, head: Char, run: String) -> String:
  match digit:
    case True{}:
      String.append(run, SCon{head, SNil{}})
    case False{}:
      ""

# the digits a text ends in, after the run read so far
def Books.trail(str: String, run: String) -> String:
  match str:
    case SNil{}:
      run
    case SCon{+head, tail}:
      Books.trail(tail, Books.trail.next(Char.is_digit(head), head, run))

# a book's timestamp: the year its id ends in (galbraith1973 is
# 1973-01-01T00:00:00.000Z), else now
def Books.ts(book: String, now: String) -> String:
  Maybe.default(&2, String,
    Books.year.if(Books.trail(book, "")), now)

# the record of a span, its paragraph offsets moved to whole-book offsets
def Books.record(+corpus: String, +book: String, +ts: String, span: Span) -> Maybe<&2, R.Record>:
  match span:
    case Span{+at, body}:
      Maybe.map(&2, R.Record, R.Record, rec => R.Record.shift(rec, at),
        R.Record.make("book:" ++ corpus ++ "/" ++ book ++ "@" ++ U32.show(at),
          ts, "book:" ++ corpus ++ "/" ++ book, book, "", "", body, ""))

# the record ahead of rest, when there is one
def Books.some(got: Maybe<&2, R.Record>, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match got:
    case None{}:
      rest
    case Some{rec}:
      rec <> rest

# the records of spans, in order; a span with no paragraph makes none
def Books.records(+corpus: String, +book: String, +ts: String, spans: List<&2, Span>) -> List<&2, R.Record>:
  match spans:
    case Nil{}:
      []
    case Con{span, rest}:
      Books.some(Books.record(corpus, book, ts, span),
        Books.records(corpus, book, ts, rest))

# a book's records, from its text and its parsed headings and pages
def Books.cut(
  +corpus: String,
  +book: String,
  +ts: String,
  +text: String,
  heads: Maybe<&2, Value.Json>,
  pages: Maybe<&2, Value.Json>
) -> List<&2, R.Record>:
  Books.records(corpus, book, ts,
    Books.spans(Books.cuts(Books.offsets.if(Books.heads(Books.items(heads)),
      Books.nums(Books.items(pages))), Books.len(text, 0)), text, 0))

# a file's text, or "" when it cannot be read
def Books.read(path: String) -> IO(String):
  do IO<String>:
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(path)
    return Result.default(&1, &1, U32 & String, String, res, "")

# ingest one book and print how many records it appended; answers the
# cursor with the book in it
def Books.book(+dir: String, +corpus: String, +book: String, +now: String, cursor: String) -> IO(String):
  do IO<String>:
    +text : String <- St.Store.read(dir ++ "/" ++ book ++ ".txt")
    heads : String <- Books.read(dir ++ "/" ++ book ++ ".heads.json")
    pages : String <- Books.read(dir ++ "/" ++ book ++ ".pages.json")
    +next : String = cursor ++ corpus ++ "/" ++ book ++ ".txt\n"
    n : U32 <- In.Ingest.run("books",
      Books.cut(corpus, book, Books.ts(book, now), text, Json.parse(heads),
        Json.parse(pages)), next)
    IO.print("book:" ++ corpus ++ "/" ++ book ++ ": " ++ U32.show(n) ++ " records")
    return next

# ingest a book unless the cursor lists it
def Books.book.if(
  done: Bool,
  +dir: String,
  +corpus: String,
  +book: String,
  +now: String,
  cursor: String
) -> IO(String):
  match done:
    case True{}:
      IO.pure(String, cursor)
    case False{}:
      Books.book(dir, corpus, book, now, cursor)

# True when hit, else what the rest says
def Books.mem.if(hit: Bool, rest: Unit -> Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      rest(Unit{})

# True when text is one of xs
def Books.mem(+text: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{head, rest}:
      Books.mem.if(String.eq(text, head), _u => Books.mem(text, rest))

# True when the cursor lists the entry
def Books.done(+entry: String, cursor: String) -> Bool:
  Books.mem(entry, String.lines(cursor))

# ingest the books, in order; answers the cursor
def Books.books(
  books: List<&2, String>,
  +dir: String,
  +corpus: String,
  +now: String,
  +cursor: String
) -> IO(String):
  match books:
    case Nil{}:
      IO.pure(String, cursor)
    case Con{+book, rest}:
      do IO<String>:
        +cur : String <- Books.book.if(
          Books.done(corpus ++ "/" ++ book ++ ".txt", cursor), dir, corpus,
          book, now, cursor)
        Books.books(rest, dir, corpus, now, cur)

# a name without .txt ahead of rest when it is a book
def Books.ids.if(book: Bool, +name: String, rest: List<&2, String>) -> List<&2, String>:
  match book:
    case True{}:
      String.take(name, Nat.sub(String.length(name), 4n)) <> rest
    case False{}:
      rest

# the book ids of a directory's names: those ending in .txt, without it
def Books.ids(names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}:
      []
    case Con{+name, rest}:
      Books.ids.if(String.ends_with(name, ".txt"), name, Books.ids(rest))

# a corpus's book names, or stop when its directory cannot be read
def Books.listed(res: Result<&1, &1, U32 & String, List<&2, String>>, +dir: String) -> IO(List<&2, String>):
  match res:
    case Fail{(code, why)}:
      St.Store.die(List<&2, String>, Sys.err.os(code, why, dir))
    case Done{names}:
      IO.pure(List<&2, String>, Books.ids(names))

# ingest the corpora, in order; answers the cursor
def Books.corpora(cs: List<&2, String>, +root: String, +now: String, cursor: String) -> IO(String):
  match cs:
    case Nil{}:
      IO.pure(String, cursor)
    case Con{+corpus, rest}:
      do IO<String>:
        +dir : String = root ++ "/" ++ corpus ++ "/text"
        res : Result<&1, &1, U32 & String, List<&2, String>> <- Sys.dir.list(dir)
        books : List<&2, String> <- Books.listed(res, dir)
        cur : String <- Books.books(books, dir, corpus, now, cursor)
        Books.corpora(rest, root, now, cur)

# the canon root: $EPISTEME_BOOKS, or ~/.local/share/canonagents
def Books.root() -> IO(String):
  do IO<String>:
    home : String <- Sys.env.or("HOME", "")
    Sys.env.or("EPISTEME_BOOKS", home ++ "/.local/share/canonagents")

# ingest every book of the corpora not yet ingested
def Books.run(cs: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +root : String <- Books.root()
    +now : String <- Sys.time.now_iso()
    cursor : String <- St.Store.cursor("books")
    _cur : String <- Books.corpora(cs, root, now, cursor)
    return Unit{}
