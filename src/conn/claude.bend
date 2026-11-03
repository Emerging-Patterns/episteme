# episteme/src/conn/claude: the Claude Code transcripts connector. The root
# is $EPISTEME_CLAUDE or ~/.claude/projects; each project directory there,
# in name order, holds transcripts <name>.jsonl and subagent transcripts
# <name>/subagents/<agent>.jsonl. Files are append-only, so the cursor
# keeps, per file, how many complete lines have been read and the bytes
# they take: a file no bigger than that is not read, and a bigger one is
# read from that byte (Chat.from). Records go to the log in batches of
# whole files, about Claude.budget() code points each, each batch carrying
# the cursor after its files. What a line becomes is Chat.records in
# src/chat.bend. IO: the trusted shell.
#
# Trusted, not proved: `episteme ingest claude` reads its cursor with
# `Store.cursor("claude")` and `Chat.ats`, one `<lines>\t<bytes>\t<file>`
# line per transcript (an older `<lines>\t<file>` line reads as
# laws/CutEndsAtLastFeed.bend says), `<file>` relative to the root `$EPISTEME_CLAUDE` or `~/.claude/projects`. It
# takes each project directory of the root in name order and, in it, each
# entry in name order: a name ending in `.jsonl` is a transcript, and any
# other entry `<x>` gives the `.jsonl` files of `<x>/subagents/`. For each
# file it opens it and reads its size with Base's `File.size`: when the size
# is not past the byte `Chat.from` of its entry starts at (`Chat.grown`), it
# reads nothing more and leaves the entry as it is; else it reads the bytes
# from there to the size with `File.read_at` and gives `Chat.after` of them:
# the records of each complete line past the skip, numbered on from the
# lines before them, with `Chat.read` (none when `Chat.keep` drops it or it
# is not JSON), project `Chat.project` of the directory and path the file's
# full path, and the file's entry after the read; a file it cannot open,
# size or read is reported on stderr and left as the cursor has it. Files are gathered whole, in that
# order, until their records reach `Claude.budget()` (4,000,000) code points
# of shard size, and then appended with one `Ingest.run`, whose batch carries
# the cursor with every gathered file's entry; the rest go in one last
# `Ingest.run`. It prints each batch's count and the total. A line is given
# once: its records and the cursor that counts it are in one batch. The cursor
# assumes transcript files are append-only and never move: a file that shrinks
# or is rewritten is not read again up to its old byte, and a file that
# moves is read again whole under its new path.
#
# Why it is trusted: It reads files and directories, which no law reaches;
# what a line becomes is laws/DecodeSkipsNonMessages.bend,
# laws/ChatRecordsKeepEveryBlock.bend, laws/ProjectDropsDash.bend and
# laws/ToolRecordsInlineOrPoint.bend. `tests/smoke.sh` checks a synthetic
# transcript and subagent transcript: the record count, a human's queued
# prompt read and a task notification's not, no compaction summary, system
# line, tool result text or text of a tool call over 4000 code points in the
# log, the pointers that `show` resolves to their transcript lines, the
# authors, a second run that reads nothing, and a line still being written
# that is read only once its line feed lands. Where a read starts and ends is
# laws/CutEndsAtLastFeed.bend, and which lines are parsed
# laws/KeepSkipsUnparsedLines.bend. A cursor written before byte offsets was
# checked on a copy of the live store: the first run read every older entry
# from byte 0, gave the line-count connector's records byte for byte, and
# wrote offsets that each end at a line feed after exactly the lines
# counted.
import Base
import ../record.bend as R
import ../chat.bend as C
import ../store.bend as St
import ../ingest.bend as In
import 0x8abe7473e8854cc69c687ee77b7d72e3/main.bend as Sys

# how far a run got: the cursor, the records read and not yet appended
# (newest file first), their code points, and the records and batches
# appended so far
type Run is Data:
  Run{seen: List<&2, C.At>, recs: List<&2, List<&2, R.Record>>,
    chars: Nat, total: U32, batches: U32}

# the code points of records a batch gathers before it is appended
def Claude.budget() -> Nat:
  4000000n

# close the file, then answer
def Claude.closed(file: File, got: Maybe<&2, List<&2, U32>>) -> IO(Maybe<&2, List<&2, U32>>):
  do IO<Maybe<&2, List<&2, U32>>>:
    File.close(file)
    return got

# the bytes a read at an offset gave, or None when it failed
def Claude.got(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Maybe<&2, List<&2, U32>>):
  (file, res) = pair
  match res:
    case Fail{_err}:
      Claude.closed(file, None{})
    case Done{bs}:
      Claude.closed(file, Some{bs})

# the bytes of a file of the size from where the read starts
def Claude.at(file: File, from: C.From, +size: U32) -> IO(Maybe<&2, List<&2, U32>>):
  match from:
    case C.From{+byte, _lines, _skip}:
      IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, Maybe<&2, List<&2, U32>>,
        File.read_at(file, byte, U32.sub(size, byte)), Claude.got)

# the bytes of a file of the size from the byte the entry starts at: none
# without a read when it has not grown
def Claude.grown(grown: Bool, file: File, +at: C.At, +size: U32) -> IO(Maybe<&2, List<&2, U32>>):
  match grown:
    case False{}:
      Claude.closed(file, Some{[]})
    case True{}:
      Claude.at(file, C.Chat.from(at), size)

# the bytes of an opened file the entry has not read, after its size
def Claude.sized(+at: C.At, pair: File & Result<&1, &1, U32 & String, U32>) -> IO(Maybe<&2, List<&2, U32>>):
  (file, res) = pair
  match res:
    case Fail{_err}:
      Claude.closed(file, None{})
    case Done{+size}:
      Claude.grown(C.Chat.grown(at, size), file, at, size)

# the bytes of an opened file the entry has not read, or None
def Claude.opened(+at: C.At, res: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, List<&2, U32>>):
  match res:
    case Fail{_err}:
      IO.pure(Maybe<&2, List<&2, U32>>, None{})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Maybe<&2, List<&2, U32>>,
        File.size(file), pair => Claude.sized(at, pair))

# the bytes of a file the entry has not read, none when it has not grown,
# or None when it cannot be read
def Claude.read(path: String, +at: C.At) -> IO(Maybe<&2, List<&2, U32>>):
  IO.bind(Result<&1, &1, U32 & String, File>, Maybe<&2, List<&2, U32>>,
    File.open(path, "r"), res => Claude.opened(at, res))

# a directory's names, or none when it cannot be read
def Claude.names(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    res : Result<&1, &1, U32 & String, List<&2, String>> <- Sys.dir.list(path)
    return Result.default(&1, &1, U32 & String, List<&2, String>, res, [])

# name ahead of rest when keep
def Claude.jsonl.if(keep: Bool, name: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      name <> rest
    case False{}:
      rest

# the names ending in .jsonl, each after the prefix
def Claude.jsonl(names: List<&2, String>, +pre: String) -> List<&2, String>:
  match names:
    case Nil{}:
      []
    case Con{+name, rest}:
      Claude.jsonl.if(String.ends_with(name, ".jsonl"), pre ++ name,
        Claude.jsonl(rest, pre))

# the subagent transcripts of <dir>/subagents, relative to the root
def Claude.subs(+root: String, +dir: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    names : List<&2, String> <- Claude.names(root ++ "/" ++ dir ++ "/subagents")
    return Claude.jsonl(names, dir ++ "/subagents/")

# the transcripts one entry of a project directory gives: a name ending
# in .jsonl is one; any other gives the .jsonl files of <name>/subagents
def Claude.name(file: Bool, +root: String, +proj: String, +name: String) -> IO(List<&2, String>):
  match file:
    case True{}:
      IO.pure(List<&2, String>, [proj ++ "/" ++ name])
    case False{}:
      Claude.subs(root, proj ++ "/" ++ name)

# the transcripts of a project directory, relative to the root, in the
# order of its entries
def Claude.files(names: List<&2, String>, +root: String, +proj: String) -> IO(List<&2, String>):
  match names:
    case Nil{}:
      IO.pure(List<&2, String>, [])
    case Con{+name, rest}:
      do IO<List<&2, String>>:
        got : List<&2, String> <- Claude.name(String.ends_with(name, ".jsonl"), root, proj, name)
        more : List<&2, String> <- Claude.files(rest, root, proj)
        return List.append(&2, String, got, more)

# the records gathered, oldest file first
def Claude.gathered(recs: List<&2, List<&2, R.Record>>) -> List<&2, R.Record>:
  List.concat(&2, R.Record, List.reverse(&2, List<&2, R.Record>, recs))

# print how many records a batch appended, when it appended any
def Claude.said(none: Bool, num: U32) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.print("chat:claude: " ++ U32.show(num) ++ " records appended")

# append the records gathered as one batch with the cursor; the run after
def Claude.flush(run: Run) -> IO(Run):
  match run:
    case Run{+seen, recs, _chars, total, batches}:
      do IO<Run>:
        +n : U32 <- In.Ingest.run("claude", Claude.gathered(recs), C.Chat.ats.text(seen))
        Claude.said(U32.is_eq(n, 0), n)
        return Run{seen, [], 0n, U32.add(total, n), U32.inc(batches)}

# the run, flushed when its records reach the budget
def Claude.flush.if(full: Bool, run: Run) -> IO(Run):
  match full:
    case True{}:
      Claude.flush(run)
    case False{}:
      IO.pure(Run, run)

# the run after a file's new lines: its records gathered and its entry
# set in the cursor
def Claude.take(run: Run, read: C.At & List<&2, R.Record>) -> IO(Run):
  match run:
    case Run{seen, got, chars, total, batches}:
      (+at, +recs) = read
      +more : Nat = Nat.add(chars, C.Chat.chars(recs))
      Claude.flush.if(Nat.is_le(Claude.budget(), more),
        Run{C.Chat.at.set(seen, at), recs <> got, more, total, batches})

# the run after a file's bytes the entry had not read: unchanged when
# there are none
def Claude.bytes(+bs: List<&2, U32>, run: Run, +at: C.At, +root: String, +proj: String, +file: String) -> IO(Run):
  match bs:
    case Nil{}:
      IO.pure(Run, run)
    case Con{_b, _rest}:
      Claude.take(run, C.Chat.after(at, bs, root ++ "/" ++ file, C.Chat.project(proj)))

# the run after a file, unchanged when it cannot be read
def Claude.file.got(
  got: Maybe<&2, List<&2, U32>>,
  run: Run,
  +at: C.At,
  +root: String,
  +proj: String,
  +file: String
) -> IO(Run):
  match got:
    case None{}:
      do IO<Run>:
        IO.print_err("episteme: cannot read " ++ root ++ "/" ++ file)
        return run
    case Some{+bs}:
      Claude.bytes(bs, run, at, root, proj, file)

# the run after a file, read from where its entry says
def Claude.file(run: Run, +root: String, +proj: String, +file: String) -> IO(Run):
  match run:
    case Run{+seen, recs, chars, total, batches}:
      +at : C.At = C.Chat.at.get(seen, file)
      do IO<Run>:
        got : Maybe<&2, List<&2, U32>> <- Claude.read(root ++ "/" ++ file, at)
        Claude.file.got(got, Run{seen, recs, chars, total, batches}, at, root, proj, file)

# the run after each file, in order
def Claude.each(files: List<&2, String>, run: Run, +root: String, +proj: String) -> IO(Run):
  match files:
    case Nil{}:
      IO.pure(Run, run)
    case Con{+file, rest}:
      do IO<Run>:
        next : Run <- Claude.file(run, root, proj, file)
        Claude.each(rest, next, root, proj)

# the run after every project, in order
def Claude.projects(projs: List<&2, String>, run: Run, +root: String) -> IO(Run):
  match projs:
    case Nil{}:
      IO.pure(Run, run)
    case Con{+proj, rest}:
      do IO<Run>:
        names : List<&2, String> <- Claude.names(root ++ "/" ++ proj)
        files : List<&2, String> <- Claude.files(names, root, proj)
        next : Run <- Claude.each(files, run, root, proj)
        Claude.projects(rest, next, root)

# print a run's total
def Claude.done(run: Run) -> IO(Unit):
  match run:
    case Run{_seen, _recs, _chars, total, _batches}:
      IO.print("chat:claude: " ++ U32.show(total) ++ " records")

# the transcripts root: $EPISTEME_CLAUDE, or ~/.claude/projects
def Claude.root() -> IO(String):
  do IO<String>:
    home : String <- Sys.env.or("HOME", "")
    Sys.env.or("EPISTEME_CLAUDE", home ++ "/.claude/projects")

# ingest every transcript line not yet read, in batches of whole files;
# prints each batch's count, then the total
def Claude.run() -> IO(Unit):
  do IO<Unit>:
    +root : String <- Claude.root()
    cursor : String <- St.Store.cursor("claude")
    projs : List<&2, String> <- Claude.names(root)
    run : Run <- Claude.projects(projs, Run{C.Chat.ats(cursor), [], 0n, 0, 0}, root)
    last : Run <- Claude.flush(run)
    Claude.done(last)
