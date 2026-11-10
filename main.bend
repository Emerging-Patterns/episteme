# episteme: primary-source Q&A over raw records, in Bend 2
#
# Trusted, not proved: `episteme sources` stops as `Store.ready` does when the
# shards are behind the log (src/ingest.bend), else prints the line `source
# records paragraphs shards`, then one line per source of the shards of the
# configured size, in source order: its records (items holding their record's
# paragraph 1), its paragraphs (the items' paragraphs) and the shards whose
# `sources` hold it. `episteme show <id>[#<n>]` prints the first record of the
# log with the id (the text after the last `#` is a paragraph number when it
# reads as one) as `Excerpt.render` writes one excerpt, with all its
# paragraphs or paragraph `n`; then, for a `ptr` of `file:<path>:<line>`, that
# line of the file, and for `git:<repo>@<hash>`, what `git --no-lazy-fetch -C
# <repo> show --stat --patch --end-of-options <hash>` prints. Commands run
# with Base's `Process.run`, which finds the program on PATH.
#
# Why it is trusted: They read the store and run `git`, which no law reaches.
# `tests/smoke.sh` checks both on the fixture, and `sources` refusing when the
# shards are behind the log.
#
# Trusted, not proved: `episteme serve [--host H] [--port P]` (default
# 127.0.0.1:18113) serves the tools `ask`, `show` and `sources` as MCP over
# streamable HTTP at /mcp with ezmcp, until the process stops. Each call does
# what its command does and answers its text as the tool result: `ask` reads
# its arguments with `Tool.ask` (laws/ToolQueryIsCliQuery.bend) and runs
# `Ask.answer`; `show` and `sources` run `show.text` and `sources.text`, the
# functions their commands print. A refusal the command would stop with (no
# filter, no question, a malformed since, shards behind the log, no healthy
# reader, no such record) is a tool result with isError, and the server goes
# on; a show without an id is refused as invalid params. A store too broken
# to read (Store.die) still stops the process.
#
# Why it is trusted: It is ezmcp's transport over the same IO as the
# commands; `tests/serve.sh` checks every tool, each refusal, both filter
# shapes and the server answering after a refused ask.
import Base
import ./src/para.bend as P
import ./src/record.bend as R
import ./src/shard.bend as S
import ./src/excerpt.bend as E
import ./src/store.bend as St
import ./src/ingest.bend as In
import ./src/conn/books.bend as Books
import ./src/conn/claude.bend as Claude
import ./src/conn/honcho.bend as Hon
import ./src/conn/git.bend as Git
import ./src/conn/intent.bend as Intent
import ./src/chat.bend as C
import ./src/filter.bend as F
import ./src/ask.bend as A
import ./src/gold.bend as G
import ./src/eval.bend as Ev
import ./src/tool.bend as T
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value
import ezmcp@0.2.0.0/main.bend as Mcp
import ezmcp@0.2.0.0/src/rpc.bend as Rpc
import ezmcp@0.2.0.0/src/server.bend as Server
import ezsys@0.1.0.0/main.bend as Sys
import shake@0.8.0.0/main.bend as Shake

# the package version marker
def version() -> String:
  "0.1.0"

# a text cut in two at a separator: what is before it and after it
type Cut is Data:
  Cut{before: String, after: String}

# one source's counts: records, paragraphs, and shards it is in
type Stat is Data:
  Stat{source: String, records: U32, paras: U32, shards: U32}

# 1 for True, 0 for False
def first.if(one: Bool) -> U32:
  match one:
    case True{}:
      1
    case False{}:
      0

# 1 when the paragraphs start with the record's first, else 0
def first(ps: List<&2, P.Para>) -> U32:
  match ps:
    case Nil{}:
      0
    case Con{pa, _rest}:
      match pa:
        case P.Para{n, _start, _end, _text}:
          first.if(U32.is_eq(n, 1))

# stat with counts added
def stat.add(st: Stat, +recs: U32, +ps: U32, +shs: U32) -> Stat:
  match st:
    case Stat{source, records, paras, shards}:
      Stat{source, U32.add(records, recs), U32.add(paras, ps), U32.add(shards, shs)}

# where src goes against the stat st: before it, in it, or after it,
# where later puts it in the rest
def stat.at(
  cmp: Cmp,
  +st: Stat,
  rest: List<&2, Stat>,
  +src: String,
  +recs: U32,
  +ps: U32,
  +shs: U32,
  later: Unit -> List<&2, Stat>
) -> List<&2, Stat>:
  match cmp:
    case LT{}:
      Stat{src, recs, ps, shs} <> st <> rest
    case EQ{}:
      stat.add(st, recs, ps, shs) <> rest
    case GT{}:
      st <> later(Unit{})

# the stat of src at its place in sts, kept in source order, with counts
# added; a new source starts at 0
def stat.put(sts: List<&2, Stat>, +src: String, +recs: U32, +ps: U32, +shs: U32) -> List<&2, Stat>:
  match sts:
    case Nil{}:
      [Stat{src, recs, ps, shs}]
    case Con{+st, +rest}:
      match st:
        case Stat{+source, _r, _p, _s}:
          stat.at(String.order(src, source), st, rest, src, recs, ps, shs,
            _u => stat.put(rest, src, recs, ps, shs))

# the counts of items added
def stat.items(its: List<&2, S.Item>, sts: List<&2, Stat>) -> List<&2, Stat>:
  match its:
    case Nil{}:
      sts
    case Con{+it, rest}:
      match it:
        case S.Item{+rec, from, upto}:
          match rec:
            case R.Record{_id, _ts, +source, _author, _thread, _parent, _paras, _ptr}:
              +ps = S.Shard.item.paras(S.Item{rec, from, upto})
              stat.items(rest, stat.put(sts, source, first(ps),
                U32.from_nat(List.length(&2, P.Para, ps)), 0))

# one shard counted for each of its sources
def stat.sources(srcs: List<&2, String>, sts: List<&2, Stat>) -> List<&2, Stat>:
  match srcs:
    case Nil{}:
      sts
    case Con{src, rest}:
      stat.sources(rest, stat.put(sts, src, 0, 0, 1))

# the counts as lines, one per source
def stat.lines(sts: List<&2, Stat>) -> String:
  match sts:
    case Nil{}:
      ""
    case Con{st, rest}:
      match st:
        case Stat{source, records, paras, shards}:
          String.concat([source, " ", U32.show(records), " ", U32.show(paras),
            " ", U32.show(shards), "\n", stat.lines(rest)])

# the counts of shards added
def stat.shards(ss: List<&2, S.Shard>, sts: List<&2, Stat>) -> List<&2, Stat>:
  match ss:
    case Nil{}:
      sts
    case Con{sh, rest}:
      match sh:
        case S.Shard{_n, items, sources, _chars, _frozen}:
          stat.shards(rest, stat.sources(sources, stat.items(items, sts)))

# the first source of a shard's sources, "" when it has none
def stat.source(srcs: List<&2, String>) -> String:
  match srcs:
    case Nil{}:
      ""
    case Con{src, _rest}:
      src

# the counts of one light added: a shard that was read by its items, an
# unread one (a frozen shard of one source) by what its source's sizes file
# holds
def stat.light(sized: Maybe<&2, Nat>, +shard: S.Shard, recs: U32, sts: List<&2, Stat>) -> List<&2, Stat>:
  match sized:
    case None{}:
      stat.shards([shard], sts)
    case Some{paras}:
      match shard:
        case S.Shard{_n, _items, sources, _chars, _frozen}:
          stat.put(sts, stat.source(sources), recs, U32.from_nat(paras), 1)

# the counts of lights added
def stat.lights(ls: List<&2, St.Light>, sts: List<&2, Stat>) -> List<&2, Stat>:
  match ls:
    case Nil{}:
      sts
    case Con{light, rest}:
      match light:
        case St.Light{shard, sized, _path, _last, recs}:
          stat.lights(rest, stat.light(sized, shard, recs, sts))

# the table of sources when the shards are not behind the log, else the
# refusal
def sources.of(behind: Maybe<&2, String>, +cap: U32) -> IO(Result<&2, &2, String, String>):
  match behind:
    case Some{why}:
      IO.pure(Result<&2, &2, String, String>, Fail{why})
    case None{}:
      do IO<Result<&2, &2, String, String>>:
        ls : List<&2, St.Light> <- St.Store.light(cap, St.Store.every())
        return Done{"source records paragraphs shards\n" ++ stat.lines(stat.lights(ls, []))}

# each source with its records, paragraphs and shards, or the refusal when
# the shards are behind the log
def sources.text() -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    cfg : St.Config <- St.Store.config()
    +cap : U32 <- St.Store.cap(cfg)
    behind : Maybe<&2, String> <- St.Store.behind(cap)
    sources.of(behind, cap)

# the text, or stop with the refusal
def written(res: Result<&2, &2, String, String>) -> IO(Unit):
  match res:
    case Fail{why}:
      St.Store.die(Unit, why)
    case Done{text}:
      IO.write(text)

# print each source with its records, paragraphs and shards
def run.sources() -> IO(Unit):
  do IO<Unit>:
    res : Result<&2, &2, String, String> <- sources.text()
    written(res)

# a wanted record id and paragraph number, if one was named
type Want is Data:
  Want{id: String, num: Maybe<&2, U32>}

# the id and number when the number read, else the whole argument
def want.num(got: Maybe<&2, U32>, id: String, arg: String) -> Want:
  match got:
    case Some{num}:
      Want{id, Some{num}}
    case None{}:
      Want{arg, None{}}

# the id and number of a cut at the last "#", when the number is one
def want.cut(got: Maybe<&2, Cut>, +arg: String) -> Want:
  match got:
    case None{}:
      Want{arg, None{}}
    case Some{Cut{id, num}}:
      want.num(U32.read(num), id, arg)

# the reversed pieces as the text before the last piece and the last piece
def cut.parts(rev: List<&2, String>, +sep: Char) -> Maybe<&2, Cut>:
  match rev:
    case Nil{}:
      None{}
    case Con{_last, Nil{}}:
      None{}
    case Con{last, Con{h, t}}:
      Some{Cut{String.join(List.reverse(&2, String, h <> t), String.from_list([sep])), last}}

# the text before the last sep and the text after it, or None
def cut.last(+str: String, +sep: Char) -> Maybe<&2, Cut>:
  cut.parts(List.reverse(&2, String, String.split(str, sep)), sep)

# `<id>` or `<id>#<n>` as a Want
def want(+arg: String) -> Want:
  want.cut(cut.last(arg, '#'), arg)

# rec when it is the one, else what comes after
def find.if(hit: Bool, rec: R.Record, after: Maybe<&2, R.Record>) -> Maybe<&2, R.Record>:
  match hit:
    case True{}:
      Some{rec}
    case False{}:
      after

# the record with the id, the first in log order, or None
def find(+id: String, recs: List<&2, R.Record>) -> Maybe<&2, R.Record>:
  match recs:
    case Nil{}:
      None{}
    case Con{+rec, rest}:
      match rec:
        case R.Record{rid, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
          find.if(String.eq(id, rid), rec, find(id, rest))

# pa ahead of rest when it is the one
def numbered.if(hit: Bool, pa: P.Para, rest: List<&2, P.Para>) -> List<&2, P.Para>:
  match hit:
    case True{}:
      pa <> rest
    case False{}:
      rest

# the paragraphs numbered num
def numbered(+num: U32, ps: List<&2, P.Para>) -> List<&2, P.Para>:
  match ps:
    case Nil{}:
      []
    case Con{+pa, rest}:
      match pa:
        case P.Para{n, _start, _end, _text}:
          numbered.if(U32.is_eq(n, num), pa, numbered(num, rest))

# the paragraphs a Want names of a record: all, or the numbered one
def picked(num: Maybe<&2, U32>, ps: List<&2, P.Para>) -> List<&2, P.Para>:
  match num:
    case None{}:
      ps
    case Some{n}:
      numbered(n, ps)

# the line at a 1-based number, or ""
def line.at(lines: List<&2, String>, num: Nat) -> String:
  match lines num:
    case Nil{} _:
      ""
    case Con{head, _rest} 1n:
      head
    case Con{_head, rest} 2n+n:
      line.at(rest, 1n+n)
    case Con{_head, _rest} 0n:
      ""

# what a show writes: its output and what goes to stderr
type Shown is Data:
  Shown{out: String, err: String}

# the line of a file read, or why it was not
def show.read(res: Result<&1, &1, U32 & String, String>, +path: String, num: String) -> Shown:
  match res:
    case Fail{(code, why)}:
      Shown{"", "episteme: " ++ Sys.err.os(code, why, path)}
    case Done{text}:
      Shown{line.at(C.Chat.lines(text),
        U32.to_nat(Maybe.default(&2, U32, U32.read(num), 0))) ++ "\n", ""}

# the line of file:<path>:<line>
def show.file(got: Maybe<&2, Cut>) -> IO(Shown):
  match got:
    case None{}:
      IO.pure(Shown, Shown{"", "episteme: a file pointer is file:<path>:<line>"})
    case Some{Cut{+path, num}}:
      do IO<Shown>:
        res : Result<&1, &1, U32 & String, String> <- Sys.file.read(path)
        return show.read(res, path, num)

# a command's output, or its failure
def ran(res: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Shown:
  match res:
    case Fail{(_code, why)}:
      Shown{"", "episteme: " ++ why}
    case Done{(_code, (out, err))}:
      Shown{out, err}

# run `git --no-lazy-fetch -C <repo> show --stat --patch --end-of-options
# <hash>`, so a hash is never read as an option and a partial clone never
# fetches, up to 256 MiB of output and a minute
def git.show(repo: String, hash: String) -> IO(Result<&1, &1, U32 & String, U32 & (String & String)>):
  Process.run("git", ["--no-lazy-fetch", "-C", repo, "show", "--stat", "--patch", "--end-of-options", hash], "",
    268435456, 60000)

# `git show --stat --patch` of git:<repo>@<hash>
def show.git(got: Maybe<&2, Cut>) -> IO(Shown):
  match got:
    case None{}:
      IO.pure(Shown, Shown{"", "episteme: a git pointer is git:<repo>@<hash>"})
    case Some{Cut{repo, hash}}:
      do IO<Shown>:
        res : Result<&1, &1, U32 & String, U32 & (String & String)> <- git.show(repo, hash)
        return ran(res)

# the pointer by its kind
def show.ptr.if(file: Bool, git: Bool, +ptr: String) -> IO(Shown):
  match file git:
    case True{} _:
      show.file(cut.last(String.drop(ptr, 5n), ':'))
    case False{} True{}:
      show.git(cut.last(String.drop(ptr, 4n), '@'))
    case False{} False{}:
      IO.pure(Shown, Shown{"", ""})

# what a pointer points at: a file's line or a commit
def show.ptr(+ptr: String) -> IO(Shown):
  show.ptr.if(String.starts_with(ptr, "file:"), String.starts_with(ptr, "git:"), ptr)

# the excerpt ahead of what the pointer shows
def show.ahead(+text: String, sh: Shown) -> Shown:
  match sh:
    case Shown{out, err}:
      Shown{text ++ out, err}

# the paragraphs of a record, then what its pointer points at
def show.rec(ps: List<&2, P.Para>, +rec: R.Record, +arg: String) -> IO(Result<&2, &2, String, Shown>):
  match ps:
    case Nil{}:
      IO.pure(Result<&2, &2, String, Shown>, Fail{"no paragraph " ++ arg})
    case Con{pa, rest}:
      match rec:
        case R.Record{_id, _ts, _source, _author, _thread, _parent, _paras, +ptr}:
          do IO<Result<&2, &2, String, Shown>>:
            sh : Shown <- show.ptr(ptr)
            return Done{show.ahead(E.Excerpt.render([E.Ex{rec, pa <> rest}]), sh)}

# the wanted record or paragraph
def show.found(got: Maybe<&2, R.Record>, num: Maybe<&2, U32>, +arg: String) -> IO(Result<&2, &2, String, Shown>):
  match got:
    case None{}:
      IO.pure(Result<&2, &2, String, Shown>, Fail{"no record " ++ arg})
    case Some{+rec}:
      match rec:
        case R.Record{_id, _ts, _source, _author, _thread, _parent, paras, _ptr}:
          show.rec(picked(num, paras), rec, arg)

# the record or paragraph a Want names
def show.want(wt: Want, +arg: String) -> IO(Result<&2, &2, String, Shown>):
  match wt:
    case Want{+id, num}:
      do IO<Result<&2, &2, String, Shown>>:
        log : List<&2, R.Record> <- St.Store.log()
        show.found(find(id, log), num, arg)

# a record, or one paragraph of it, and what its pointer points at; or the
# refusal when there is none
def show.text(+arg: String) -> IO(Result<&2, &2, String, Shown>):
  show.want(want(arg), arg)

# stderr's text, when there is any
def show.err(+err: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(err), IO.pure(Unit, Unit{}), IO.print_err(err))

# print a show, or stop with its refusal
def show.out(res: Result<&2, &2, String, Shown>) -> IO(Unit):
  match res:
    case Fail{why}:
      St.Store.die(Unit, why)
    case Done{Shown{out, +err}}:
      do IO<Unit>:
        IO.write(out)
        show.err(err)

# print a record, or one paragraph of it
def show(+arg: String) -> IO(Unit):
  do IO<Unit>:
    res : Result<&2, &2, String, Shown> <- show.text(arg)
    show.out(res)

# --- serve ---

# strings as JSON strings
def strs(xs: List<&2, String>) -> List<&2, Value.Json>:
  match xs:
    case Nil{}:
      []
    case Con{x, rest}:
      Json.str(x) <> strs(rest)

# a tool's input schema: an object of string properties, some required
def schema(props: List<&1, String & Value.Json>, req: List<&2, String>) -> Value.Json:
  Json.obj([("type", Json.str("object")), ("properties", Json.obj(props)),
    ("required", Json.arr(strs(req)))])

# a string property with its description
def prop(+name: String, desc: String) -> String & Value.Json:
  (name, Json.obj([("type", Json.str("string")), ("description", Json.str(desc))]))

# what the server tells a client about its tools
def serve.instructions() -> String:
  String.concat([
    "episteme returns verbatim, cited excerpts of the primary record: ingested books, ",
    "Claude Code transcripts, Honcho chats, git history and the intent file. Readers only ",
    "pick paragraphs; nothing is summarized, so answer from the excerpts and cite every ",
    "claim as <record id>#<n>. Later excerpts are the current state. Call sources first ",
    "when unsure what to filter on; pass the narrowest filter that can hold the answer, ",
    "and since for recent chat or git work. A footer naming failed shards means those ",
    "shards were not read: report it, and never read their gap as the record saying nothing."])

# the tools episteme serves
def serve.srv() -> Server.Server:
  Mcp.server("episteme", version(), serve.instructions(), [
    Mcp.tool("ask",
      "Read every shard the filter hits for a question and return verbatim excerpts in time order, then a footer of the reads. Cost is the shards read: keep the filter narrow.",
      schema([prop("question", "The question, in plain words, with the names and terms the record would use"),
          prop("filter", "Sources to read, comma-separated: exact sources and prefixes ending in /, e.g. book:<corpus>/ or chat:claude/<project>,git:<repo>. Required; a filter over every chat is refused"),
          prop("since", "Read only records at or after this UTC date or time: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ (chat and git only)")],
        ["question", "filter"])),
    Mcp.tool("show",
      "Return a whole record, or one paragraph of it, and what its pointer points at (a file line or a git patch).",
      schema([prop("id", "<record id> or <record id>#<n>, as cited in an excerpt")], ["id"])),
    Mcp.tool("sources",
      "List each source with its records, paragraphs and shards.",
      schema([], []))])

# a text or the refusal, as a tool result
def serve.result(res: Result<&2, &2, String, String>) -> Rpc.Out:
  match res:
    case Fail{why}:
      Mcp.ok(Mcp.result.error(why))
    case Done{text}:
      Mcp.ok(Mcp.result.text(text))

# an ask call: refused as its arguments read, else answered
def serve.ask(query: Result<&2, &2, String, T.Query>) -> IO(Rpc.Out):
  match query:
    case Fail{why}:
      IO.pure(Rpc.Out, Mcp.ok(Mcp.result.error(why)))
    case Done{T.Query{filter, since, question}}:
      do IO<Rpc.Out>:
        res : Result<&2, &2, String, String> <- A.Ask.answer(filter, since, question)
        return serve.result(res)

# a show as one text: its output, then what went to stderr
def serve.shown(res: Result<&2, &2, String, Shown>) -> Rpc.Out:
  match res:
    case Fail{why}:
      Mcp.ok(Mcp.result.error(why))
    case Done{Shown{+out, +err}}:
      Mcp.ok(Mcp.result.text(Bool.pick(String, String.is_empty(err), out, out ++ "\n" ++ err)))

# a show call: refused without an id
def serve.show(id: Maybe<&2, String>) -> IO(Rpc.Out):
  match id:
    case None{}:
      IO.pure(Rpc.Out, Mcp.refuse.params("show needs an id"))
    case Some{+id}:
      do IO<Rpc.Out>:
        res : Result<&2, &2, String, Shown> <- show.text(id)
        return serve.shown(res)

# a sources call
def serve.sources() -> IO(Rpc.Out):
  do IO<Rpc.Out>:
    res : Result<&2, &2, String, String> <- sources.text()
    return serve.result(res)

# a tool call by name; ezmcp calls only the tools the table names
def serve.tool.if(ask: Bool, shw: Bool, +args: Value.Json) -> IO(Rpc.Out):
  match ask shw:
    case True{} _:
      serve.ask(T.Tool.ask(args))
    case False{} True{}:
      serve.show(Json.as_str(Json.get(args, "id")))
    case False{} False{}:
      serve.sources()

# a tool call by its name
def serve.named(+name: String, args: Value.Json) -> IO(Rpc.Out):
  serve.tool.if(String.eq(name, "ask"), String.eq(name, "show"), args)

# the runner: one tool call
def serve.run(name: String, args: Value.Json) -> IO(Rpc.Out):
  serve.named(name, args)

# serve the tools as MCP over streamable HTTP at /mcp on host:port until the
# process stops (4294967295 connections), each connection on its own fork
def serve(+host: String, +port: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print_err("episteme: serving MCP at http://" ++ host ++ ":" ++ U32.show(port) ++ "/mcp")
    Mcp.http.serve(~serve.run, ~serve.srv(), ~"/mcp", ~[], host, port, 4294967295)

# the commands episteme takes
def spec() -> Shake.Cli:
  Shake.app("episteme", "Primary-source Q&A over raw records.", Some{version()}, [],
    [Shake.sub("ingest", "Append new records to the log and pack them into shards; alone, pack log batches the shards lack.",
      [Shake.flag("reshard", None{}, Some{"reshard"},
        "Pack the whole log again at the configured shard size"),
       Shake.flag("all", None{}, Some{"all"},
        "Run the claude, git, intent and honcho connectors, in that order")],
      [Shake.sub("books", "Ingest canon books, one record per section.",
        [Shake.rest("corpora", "Corpus names under the canon root", True{}, None{}, [])],
        []),
       Shake.sub("claude", "Ingest Claude Code transcripts, one record per message, tool call and tool result.",
        [], []),
       Shake.sub("honcho", "Ingest Honcho's raw messages, one record per message.",
        [], []),
       Shake.sub("git", "Ingest the history of each git repo under ~/projects and ~/projects/bend, one record per commit.",
        [], []),
       Shake.sub("intent", "Ingest intent.md under the data directory as one record when its text changed.",
        [], [])]),
     Shake.sub("sources", "List each source with its records, paragraphs and shards.", [], []),
     Shake.sub("show", "Print a record, or one paragraph of it.",
       [Shake.pos("id", "<record id> or <record id>#<n>", True{}, None{}, [])], []),
     Shake.sub("serve", "Serve ask, show and sources as MCP tools over streamable HTTP at /mcp.",
       [Shake.opt("host", None{}, Some{"host"}, "The address to bind", False{}, Some{"127.0.0.1"}, []),
        Shake.opt("port", None{}, Some{"port"}, "The port to bind", False{}, Some{"18113"}, [])], []),
     Shake.sub("ask", "Read every shard the filter hits for a question; print verbatim excerpts.",
       [Shake.many("filter", None{}, Some{"filter"},
         "Sources to read: values and prefixes ending in /, comma-separated", False{}, None{}, []),
        Shake.opt("since", None{}, Some{"since"},
          "Read only records at or after this UTC date or time: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ",
          False{}, None{}, []),
        Shake.flag("json", None{}, Some{"json"}, "Print one JSON object of excerpts and reads"),
        Shake.pos("question", "The question", True{}, None{}, [])], []),
     Shake.sub("eval-import", "Print a canon gold question set as questions.jsonl lines.",
       [Shake.pos("dir", "The canon corpus data directory, holding index.sqlite and text/",
         True{}, None{}, []),
        Shake.pos("questions", "The questions.yaml", True{}, None{}, []),
        Shake.pos("corpus", "The corpus name the books were ingested under", True{}, None{}, [])],
       []),
     Shake.sub("eval", "Run every question through ask and score recall of its gold spans.",
       [Shake.opt("label", None{}, Some{"label"}, "The run's name in runs/eval-<label>-<time>",
         True{}, None{}, []),
        Shake.pos("questions", "The questions.jsonl", True{}, None{}, [])], [])])

# the git connector, the intent connector, or none: a bare ingest only
# catches the shards up with the log
def ingest.rest(git: Bool, intent: Bool) -> IO(Unit):
  match git intent:
    case True{} _:
      Git.Git.run()
    case False{} True{}:
      Intent.Intent.run()
    case False{} False{}:
      IO.pure(Unit, Unit{})

# every connector that needs no argument, honcho last since it stops the
# run with exit 1 when Honcho cannot be reached
def ingest.all() -> IO(Unit):
  do IO<Unit>:
    Claude.Claude.run()
    Git.Git.run()
    Intent.Intent.run()
    Hon.Honcho.run()

# the books connector, the claude connector, the honcho connector, else
# what ingest.rest picks
def ingest.go(
  books: Maybe<&2, Shake.Matched>,
  claude: Bool,
  honcho: Bool,
  git: Bool,
  intent: Bool
) -> IO(Unit):
  match books claude honcho:
    case Some{bm} _ _:
      Books.Books.run(Shake.get_all(bm, "corpora"))
    case None{} True{} _:
      Claude.Claude.run()
    case None{} False{} True{}:
      Hon.Honcho.run()
    case None{} False{} False{}:
      ingest.rest(git, intent)

# True when the subcommand was given
def given(got: Maybe<&2, Shake.Matched>) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{_m}:
      True{}

# every connector with --all, else the one ingest bound
def ingest.pick(all: Bool, +found: Shake.Matched) -> IO(Unit):
  match all:
    case True{}:
      ingest.all()
    case False{}:
      ingest.go(Shake.sub_of(found, "books"), given(Shake.sub_of(found, "claude")),
        given(Shake.sub_of(found, "honcho")), given(Shake.sub_of(found, "git")),
        given(Shake.sub_of(found, "intent")))

# a reshard; else the shards caught up with the log, then every connector
# with --all or the one ingest bound
def ingest.locked(reshard: Bool, +found: Shake.Matched) -> IO(Unit):
  match reshard:
    case True{}:
      do IO<Unit>:
        n : U32 <- In.Ingest.reshard()
        IO.print("reshard: " ++ U32.show(n) ++ " shards")
    case False{}:
      do IO<Unit>:
        In.Ingest.caught()
        ingest.pick(Shake.on(found, "all"), found)

# run ingest with what it bound, holding the lock from its first step to
# its last (Store.die and Store.exit remove it on a failure)
def ingest(+found: Shake.Matched) -> IO(Unit):
  do IO<Unit>:
    St.Store.lock()
    ingest.locked(Shake.on(found, "reshard"), found)
    St.Store.unlock()

# help when it was asked for, else the error and exit 2
def failed.help(path: Maybe<&2, List<&2, String>>, +err: Shake.ParseErr) -> IO(Unit):
  match path:
    case Some{p}:
      IO.write(Shake.help(spec(), p))
    case None{}:
      do IO<Unit>:
        IO.print_err(Shake.err_text(spec(), err))
        IO.exit(2)

# report a failed parse: help on stdout, anything else on stderr
def failed(+err: Shake.ParseErr) -> IO(Unit):
  failed.help(Shake.help_path(err), err)

# ingest with its own bindings
def ingest.at(got: Maybe<&2, Shake.Matched>) -> IO(Unit):
  match got:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{m}:
      ingest(m)

# show with its own bindings
def show.at(got: Maybe<&2, Shake.Matched>) -> IO(Unit):
  match got:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{m}:
      show(Maybe.default(&2, String, Shake.get(m, "id"), ""))

# ask with its own bindings, exiting with its code
def ask.at(got: Maybe<&2, Shake.Matched>) -> IO(Unit):
  match got:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{+m}:
      do IO<Unit>:
        code : U32 <- A.Ask.run(F.Filter.parse(Shake.get_all(m, "filter")),
          Shake.get(m, "since"),
          Maybe.default(&2, String, Shake.get(m, "question"), ""), Shake.on(m, "json"))
        IO.exit(code)

# serve on the port when it read, else stop with exit 2
def serve.port(got: Maybe<&2, U32>, +host: String) -> IO(Unit):
  match got:
    case None{}:
      IO.die(Unit, 2, "episteme: --port must be a number")
    case Some{port}:
      serve(host, port)

# serve with its own bindings; a port that does not read is refused
def serve.at(got: Maybe<&2, Shake.Matched>) -> IO(Unit):
  match got:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{+m}:
      serve.port(U32.read(Maybe.default(&2, String, Shake.get(m, "port"), "18113")),
        Maybe.default(&2, String, Shake.get(m, "host"), "127.0.0.1"))

# eval-import with its own bindings
def import.at(got: Maybe<&2, Shake.Matched>) -> IO(Unit):
  match got:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{+m}:
      G.Gold.run(Maybe.default(&2, String, Shake.get(m, "dir"), ""),
        Maybe.default(&2, String, Shake.get(m, "questions"), ""),
        Maybe.default(&2, String, Shake.get(m, "corpus"), ""))

# eval with its own bindings, exiting with its code
def eval.at(got: Maybe<&2, Shake.Matched>) -> IO(Unit):
  match got:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{+m}:
      do IO<Unit>:
        code : U32 <- Ev.Eval.run(Maybe.default(&2, String, Shake.get(m, "questions"), ""),
          Maybe.default(&2, String, Shake.get(m, "label"), ""))
        IO.exit(code)

# the other commands by name: serve, eval-import, else eval
def command.eval(srv: Bool, imp: Bool, +found: Shake.Matched) -> IO(Unit):
  match srv imp:
    case True{} _:
      serve.at(Shake.sub_of(found, "serve"))
    case False{} True{}:
      import.at(Shake.sub_of(found, "eval-import"))
    case False{} False{}:
      eval.at(Shake.sub_of(found, "eval"))

# the command by name: ingest, sources, ask, show, else serve or an eval
# command
def command.if(ing: Bool, src: Bool, ask: Bool, shw: Bool, +name: String, +found: Shake.Matched) -> IO(Unit):
  match ing src ask shw:
    case True{} _ _ _:
      ingest.at(Shake.sub_of(found, "ingest"))
    case False{} True{} _ _:
      run.sources()
    case False{} False{} True{} _:
      ask.at(Shake.sub_of(found, "ask"))
    case False{} False{} False{} True{}:
      show.at(Shake.sub_of(found, "show"))
    case False{} False{} False{} False{}:
      command.eval(String.eq(name, "serve"), String.eq(name, "eval-import"), found)

# run the selected command
def command(+name: String, +found: Shake.Matched) -> IO(Unit):
  command.if(String.eq(name, "ingest"), String.eq(name, "sources"),
    String.eq(name, "ask"), String.eq(name, "show"), name, found)

# run a parse's command, or the top help when none was named
def run.matched(name: Maybe<&2, String>, +found: Shake.Matched) -> IO(Unit):
  match name:
    case None{}:
      IO.write(Shake.help(spec(), []))
    case Some{n}:
      command(n, found)

# run what the command line asks
def run(got: Result<&2, &2, Shake.ParseErr, Shake.Matched>) -> IO(Unit):
  match got:
    case Fail{err}:
      failed(err)
    case Done{+found}:
      run.matched(Shake.sub_name(found), found)

# the entry point
def main() -> IO(Unit):
  do IO<Unit>:
    av : List<&2, String> <- Shake.argv()
    run(Shake.parse(spec(), av))
