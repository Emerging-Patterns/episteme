# episteme: primary-source Q&A over raw records, in Bend 2
#
# Trusted, not proved: `episteme sources` stops as `Store.ready` does when the
# shards are behind the log (src/ingest.bend), else prints the line `source
# records paragraphs shards`, then one line per source of the shards of the
# configured size, in source order: its records (items holding their record's
# paragraph 1), its paragraphs (the items' paragraphs) and the shards whose
# `sources` hold it. `episteme show <id>[#<n>]` prints the current record of
# the log with the id, `Live.find` (laws/LiveKeepsLastVersion.bend): the last
# record with it, and none when that one is a removal (the text after the
# last `#` is a paragraph number when it reads as one). When the id names a
# source (`Live.source`) whose directory of shards of the configured size
# holds files, and the shards are not behind the log, it reads only that
# directory's shards and takes `Live.pick` of the records they hold, which
# is the same record (laws/ShowReadsOneSource.bend); otherwise it reads the
# whole log as `Excerpt.render` writes one excerpt, with all its
# paragraphs or paragraph `n`; then, for a `ptr` of `file:<path>:<line>`, that
# line of the file, and for `git:<repo>@<hash>`, what `git --no-lazy-fetch -C
# <repo> show --stat --patch --end-of-options <hash>` prints. Commands run
# with Base's `Process.run`, which finds the program on PATH. An argument
# that names a run file (`Cli.run`, laws/ShowReadsRunFiles.bend) is read
# first: `episteme show runs/<run>/<file>` prints the file at that path under
# `Store.home()`, a file `ask` wrote there, or refuses with `no run file
# <arg>` when it cannot be read. That no link under `runs/` leads out of it
# is assumed: episteme makes none.
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
# `Ask.answer`, whose text is what `ask` prints, with the run files'
# `INDEX.md` after `Read.more`'s line when the run is not whole; `show` and
# `sources` run `show.text` and `sources.text`, the functions their commands
# print. A refusal the command would stop with (no
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
import ./src/live.bend as L
import ./src/store.bend as St
import ./src/ingest.bend as In
import ./src/conn/records.bend as Recs
import ./src/filter.bend as F
import ./src/ask.bend as A
import ./src/gold.bend as G
import ./src/eval.bend as Ev
import ./src/tool.bend as T
import ./src/cli.bend as Cl
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value
import ezmcp@0.5.0.0/main.bend as Mcp
import ezmcp@0.5.0.0/src/rpc.bend as Rpc
import ezmcp@0.5.0.0/src/server.bend as Server
import ezsys@0.2.0.0/main.bend as Sys
import shake@0.9.0.0/main.bend as Shake

# the counts of lights added
def stat.lights(ls: List<&2, St.Light>, sts: List<&2, Cl.Stat>) -> List<&2, Cl.Stat>:
  match ls:
    case Nil{}:
      sts
    case Con{light, rest}:
      match light:
        case St.Light{shard, sized, _path, _last, recs}:
          stat.lights(rest, Cl.Cli.stat.light(sized, shard, recs, sts))

# the table of sources when the shards are not behind the log, else the
# refusal
def sources.of(behind: Maybe<&2, String>, +cap: U32) -> IO(Result<&2, &2, String, String>):
  match behind:
    case Some{why}:
      IO.pure(Result<&2, &2, String, String>, Fail{why})
    case None{}:
      do IO<Result<&2, &2, String, String>>:
        ls : List<&2, St.Light> <- St.Store.light(cap, St.Store.every())
        return Done{"source records paragraphs shards\n" ++ Cl.Cli.stat.lines(stat.lights(ls, []))}

# each source with its records, paragraphs and shards, or the refusal when
# the shards are behind the log
def sources.text() -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    cfg : St.Config <- St.Store.config()
    +cap : U32 <- St.Store.cap(cfg)
    behind : Maybe<&2, String> <- St.Store.behind(cap)
    sources.of(behind, cap)

# the text, or stop with the refusal
def written(res: Result<&2, &2, String, String>) -> IO(Unit):  # noqa: L001 IO: prints or stops
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

# the line of a file read, or why it was not
def show.read(res: Result<&1, &1, U32 & String, String>, +path: String, num: String) -> Cl.Shown:
  match res:
    case Fail{(code, why)}:
      Cl.Shown{"", "episteme: " ++ Sys.err.os(code, why, path)}
    case Done{text}:
      Cl.Shown{line.at(String.lines(text),
        U32.to_nat(Maybe.default(&2, U32, U32.read(num), 0))) ++ "\n", ""}

# the line of file:<path>:<line>
def show.file(got: Maybe<&2, Cl.Cut>) -> IO(Cl.Shown):
  match got:
    case None{}:
      IO.pure(Cl.Shown, Cl.Shown{"", "episteme: a file pointer is file:<path>:<line>"})
    case Some{Cl.Cut{+path, num}}:
      do IO<Cl.Shown>:
        res : Result<&1, &1, U32 & String, String> <- Sys.file.read(path)
        return show.read(res, path, num)

# run `git --no-lazy-fetch -C <repo> show --stat --patch --end-of-options
# <hash>`, so a hash is never read as an option and a partial clone never
# fetches, up to 256 MiB of output and a minute
def git.show(repo: String, hash: String) -> IO(Result<&1, &1, U32 & String, U32 & (String & String)>):
  Process.run("git", ["--no-lazy-fetch", "-C", repo, "show", "--stat", "--patch", "--end-of-options", hash], "",
    268435456, 60000)

# `git show --stat --patch` of git:<repo>@<hash>
def show.git(got: Maybe<&2, Cl.Cut>) -> IO(Cl.Shown):
  match got:
    case None{}:
      IO.pure(Cl.Shown, Cl.Shown{"", "episteme: a git pointer is git:<repo>@<hash>"})
    case Some{Cl.Cut{repo, hash}}:
      do IO<Cl.Shown>:
        res : Result<&1, &1, U32 & String, U32 & (String & String)> <- git.show(repo, hash)
        return Cl.Cli.ran(res)

# the pointer by its kind
def show.ptr.if(file: Bool, git: Bool, +ptr: String) -> IO(Cl.Shown):
  match file git:
    case True{} _:
      show.file(Cl.Cli.cut.last(String.drop(ptr, 5n), ':'))
    case False{} True{}:
      show.git(Cl.Cli.cut.last(String.drop(ptr, 4n), '@'))
    case False{} False{}:
      IO.pure(Cl.Shown, Cl.Shown{"", ""})

# what a pointer points at: a file's line or a commit
def show.ptr(+ptr: String) -> IO(Cl.Shown):
  show.ptr.if(String.starts_with(ptr, "file:"), String.starts_with(ptr, "git:"), ptr)

# the excerpt ahead of what the pointer shows
def show.ahead(+text: String, sh: Cl.Shown) -> Cl.Shown:
  match sh:
    case Cl.Shown{out, err}:
      Cl.Shown{text ++ out, err}

# the paragraphs of a record, then what its pointer points at
def show.rec(ps: List<&2, P.Para>, +rec: R.Record, +arg: String) -> IO(Result<&2, &2, String, Cl.Shown>):
  match ps:
    case Nil{}:
      IO.pure(Result<&2, &2, String, Cl.Shown>, Fail{"no paragraph " ++ arg})
    case Con{pa, rest}:
      match rec:
        case R.Record{_id, _ts, _source, _author, _thread, _parent, _paras, +ptr}:
          do IO<Result<&2, &2, String, Cl.Shown>>:
            sh : Cl.Shown <- show.ptr(ptr)
            return Done{show.ahead(E.Excerpt.render([E.Ex{rec, pa <> rest}]), sh)}

# the wanted record or paragraph
def show.found(got: Maybe<&2, R.Record>, num: Maybe<&2, U32>, +arg: String) -> IO(Result<&2, &2, String, Cl.Shown>):
  match got:
    case None{}:
      IO.pure(Result<&2, &2, String, Cl.Shown>, Fail{"no record " ++ arg})
    case Some{+rec}:
      match rec:
        case R.Record{_id, _ts, _source, _author, _thread, _parent, paras, _ptr}:
          show.rec(Cl.Cli.picked(num, paras), rec, arg)

# the current record with the id, from a pass over the whole log
def show.log(+id: String) -> IO(Maybe<&2, R.Record>):
  do IO<Maybe<&2, R.Record>>:
    log : List<&2, R.Record> <- St.Store.log()
    return L.Live.find(id, log)

# the record with the id among those a source directory's shards hold, or
# the log's when the directory holds nothing
def show.dir(empty: Bool, +dir: String, +id: String) -> IO(Maybe<&2, R.Record>):
  match empty:
    case True{}:
      show.log(id)
    case False{}:
      do IO<Maybe<&2, R.Record>>:
        ss : List<&2, S.Shard> <- St.Store.shards.in(dir)
        return L.Live.pick(id, L.Live.held(ss))

# the current record with the id: from the shards of the source it names
# when it names one and the shards are not behind the log, else from the log
def show.lookup(
  behind: Maybe<&2, String>,
  src: Maybe<&2, String>,
  +cap: U32,
  +id: String
) -> IO(Maybe<&2, R.Record>):
  match behind src:
    case None{} Some{named}:
      do IO<Maybe<&2, R.Record>>:
        +dir : String <- St.Store.src(cap, named)
        names : List<&2, String> <- St.Store.names(dir)
        show.dir(List.is_empty(&2, String, names), dir, id)
    case _ _:
      show.log(id)

# the record or paragraph a Want names
def show.want(wt: Cl.Want, +arg: String) -> IO(Result<&2, &2, String, Cl.Shown>):
  match wt:
    case Cl.Want{+id, num}:
      do IO<Result<&2, &2, String, Cl.Shown>>:
        cfg : St.Config <- St.Store.config()
        +cap : U32 <- St.Store.cap(cfg)
        behind : Maybe<&2, String> <- St.Store.behind(cap)
        got : Maybe<&2, R.Record> <- show.lookup(behind, L.Live.source(id), cap, id)
        show.found(got, num, arg)

# a record, or one paragraph of it, and what its pointer points at; or the
# refusal when there is none
def show.record(+arg: String) -> IO(Result<&2, &2, String, Cl.Shown>):
  show.want(Cl.Cli.want(arg), arg)

# a run file's text, or the refusal when it was not read
def show.ran(res: Result<&1, &1, U32 & String, String>, arg: String) -> Result<&2, &2, String, Cl.Shown>:
  match res:
    case Fail{_why}:
      Fail{"no run file " ++ arg}
    case Done{text}:
      Done{Cl.Shown{text, ""}}

# the run file at a path under the home
def show.run(path: String, +arg: String) -> IO(Result<&2, &2, String, Cl.Shown>):
  do IO<Result<&2, &2, String, Cl.Shown>>:
    full : String <- St.Store.path(path)
    res : Result<&1, &1, U32 & String, String> <- Sys.file.read(full)
    return show.ran(res, arg)

# the run file the argument names, else the record
def show.pick(got: Maybe<&2, String>, +arg: String) -> IO(Result<&2, &2, String, Cl.Shown>):
  match got:
    case Some{path}:
      show.run(path, arg)
    case None{}:
      show.record(arg)

# a run file; or a record, or one paragraph of it, and what its pointer
# points at; or the refusal when there is none
def show.text(+arg: String) -> IO(Result<&2, &2, String, Cl.Shown>):
  show.pick(Cl.Cli.run(arg), arg)

# stderr's text, when there is any
def show.err(+err: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(err), IO.pure(Unit, Unit{}), IO.print_err(err))

# print a show, or stop with its refusal
def show.out(res: Result<&2, &2, String, Cl.Shown>) -> IO(Unit):
  match res:
    case Fail{why}:
      St.Store.die(Unit, why)
    case Done{Cl.Shown{out, +err}}:
      do IO<Unit>:
        IO.write(out)
        show.err(err)

# print a record, or one paragraph of it
def show(+arg: String) -> IO(Unit):  # noqa: L001 IO command: reads the log and the pointed-at file or repo
  do IO<Unit>:
    res : Result<&2, &2, String, Cl.Shown> <- show.text(arg)
    show.out(res)

# --- serve ---

# what the server tells a client about its tools
def serve.instructions() -> String:
  String.concat([
    "episteme returns verbatim, cited excerpts of the primary record: the records ingested ",
    "into it, one source each. Readers only ",
    "pick paragraphs; nothing is summarized, so answer from the excerpts and cite every ",
    "claim as <record id>#<n>: the id is on the excerpt's ### line, the number on the ",
    "paragraph's. Later excerpts are the current state. Call sources first ",
    "when unsure what to filter on; pass the narrowest filter that can hold the answer, ",
    "and since for recent work. A footer naming failed shards means those ",
    "shards were not read: report it, and never read their gap as the record saying nothing."])

# the tools episteme serves
def serve.srv() -> Server.Server:
  Mcp.server("episteme", Cl.Cli.version(), serve.instructions(), [
    Mcp.tool("ask",
      "Read every shard the filter hits for a question and return verbatim excerpts in time order, then a footer of the reads. Cost is the shards read: keep the filter narrow.",
      Cl.Cli.schema([Cl.Cli.prop("question", "The question, in plain words, with the names and terms the record would use"),
          Cl.Cli.prop("filter", "Sources to read, comma-separated: exact sources and prefixes ending in /, e.g. <kind>:<name> or <kind>:<prefix>/. Required; a filter the store refuses as too wide is refused with what to name instead"),
          Cl.Cli.prop("since", "Read only records at or after this UTC date or time: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ"),
          Cl.Cli.prop("author", "Return only excerpts by these authors, comma-separated, each a record's author as an excerpt header shows it. Set it whenever the question is about what one speaker said: the user's name for the user's own typed lines")],
        ["question", "filter"])),
    Mcp.tool("show",
      "Return a whole record, or one paragraph of it, and what its pointer points at (a file line or a git patch).",
      Cl.Cli.schema([Cl.Cli.prop("id", "<record id> or <record id>#<n>, as cited in an excerpt; or runs/<run>/<file>, a run file an ask named")], ["id"])),
    Mcp.tool("sources",
      "List each source with its records, paragraphs and shards.",
      Cl.Cli.schema([], []))])

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
    case Done{T.Query{filter, since, who, question}}:
      do IO<Rpc.Out>:
        res : Result<&2, &2, String, String> <- A.Ask.answer(filter, since, who, question)
        return serve.result(res)

# a show as one text: its output, then what went to stderr
def serve.shown(res: Result<&2, &2, String, Cl.Shown>) -> Rpc.Out:
  match res:
    case Fail{why}:
      Mcp.ok(Mcp.result.error(why))
    case Done{Cl.Shown{+out, +err}}:
      Mcp.ok(Mcp.result.text(Bool.pick(String, String.is_empty(err), out, out ++ "\n" ++ err)))

# a show call: refused without an id
def serve.show(id: Maybe<&2, String>) -> IO(Rpc.Out):
  match id:
    case None{}:
      IO.pure(Rpc.Out, Mcp.refuse.params("show needs an id"))
    case Some{+id}:
      do IO<Rpc.Out>:
        res : Result<&2, &2, String, Cl.Shown> <- show.text(id)
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
      do IO<Rpc.Out>:
        refs : List<&2, F.Refusal> <- St.Store.refusals()
        serve.ask(T.Tool.ask(refs, args))
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
def serve(+host: String, +port: U32) -> IO(Unit):  # noqa: L001 IO: serves MCP over HTTP until the process stops
  do IO<Unit>:
    IO.print_err("episteme: serving MCP at http://" ++ host ++ ":" ++ U32.show(port) ++ "/mcp")
    Mcp.http.serve(~serve.run, ~serve.srv(), ~"/mcp", ~[], host, port, 4294967295)

# store the records input, when there is one; a bare ingest only catches
# the shards up with the log
def ingest.pick(records: Maybe<&2, Shake.Matched>) -> IO(Unit):
  match records:
    case Some{+rm}:
      Recs.Records.run(Maybe.default(&2, String, Shake.get(rm, "input"), "-"), Shake.on(rm, "complete"))
    case None{}:
      IO.pure(Unit, Unit{})

# a reshard; else the shards caught up with the log, then the records
# input
def ingest.locked(reshard: Bool, +found: Shake.Matched) -> IO(Unit):
  match reshard:
    case True{}:
      do IO<Unit>:
        n : U32 <- In.Ingest.reshard()
        IO.print("reshard: " ++ U32.show(n) ++ " shards")
    case False{}:
      do IO<Unit>:
        In.Ingest.caught()
        ingest.pick(Shake.sub_of(found, "records"))

# run ingest with what it bound, holding the lock from its first step to
# its last (Store.die and Store.exit remove it on a failure)
def ingest(+found: Shake.Matched) -> IO(Unit):  # noqa: L001 IO command: holds the store lock around the ingest
  do IO<Unit>:
    St.Store.lock()
    ingest.locked(Shake.on(found, "reshard"), found)
    St.Store.unlock()

# help when it was asked for, else the error and exit 2
def failed.help(path: Maybe<&2, List<&2, String>>, +err: Shake.ParseErr) -> IO(Unit):
  match path:
    case Some{p}:
      IO.write(Shake.help(Cl.Cli.spec(), p))
    case None{}:
      do IO<Unit>:
        IO.print_err(Shake.err_text(Cl.Cli.spec(), err))
        IO.exit(2)

# report a failed parse: help on stdout, anything else on stderr
def failed(+err: Shake.ParseErr) -> IO(Unit):  # noqa: L001 IO: prints help or the parse error and exits 2
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
        refs : List<&2, F.Refusal> <- St.Store.refusals()
        code : U32 <- A.Ask.run(refs, F.Filter.parse(Shake.get_all(m, "filter")),
          Shake.get(m, "since"), F.Filter.who(Shake.get(m, "author")),
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
def command(+name: String, +found: Shake.Matched) -> IO(Unit):  # noqa: L001 IO: runs the selected command
  command.if(String.eq(name, "ingest"), String.eq(name, "sources"),
    String.eq(name, "ask"), String.eq(name, "show"), name, found)

# run a parse's command, or the top help when none was named
def run.matched(name: Maybe<&2, String>, +found: Shake.Matched) -> IO(Unit):
  match name:
    case None{}:
      IO.write(Shake.help(Cl.Cli.spec(), []))
    case Some{n}:
      command(n, found)

# run what the command line asks
def run(got: Result<&2, &2, Shake.ParseErr, Shake.Matched>) -> IO(Unit):  # noqa: L001 IO entry point
  match got:
    case Fail{err}:
      failed(err)
    case Done{+found}:
      run.matched(Shake.sub_name(found), found)

# the entry point
def main() -> IO(Unit):  # noqa: L001 IO entry point
  do IO<Unit>:
    av : List<&2, String> <- Shake.argv()
    run(Shake.parse(Cl.Cli.spec(), av))
