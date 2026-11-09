# episteme/src/conn/git: the git history connector. The repos are the
# directories holding a .git directory (linked worktrees skipped) among
# the entries of the root, $EPISTEME_PROJECTS or ~/projects, and of
# <root>/bend, each in name order; a repo <root>/<x> is git:<x> and a repo
# <root>/bend/<x> is git:<x> too. It only runs read-only git commands
# (log, rev-list, merge-base), each with --no-lazy-fetch. The cursor keeps,
# per repo path, the tips read, and a read takes the commits HEAD reaches
# and no tip does. Records go to the log in
# batches of whole repos, about Git.budget() code points each, each batch
# carrying the cursor after its repos. What a commit becomes is
# src/git.bend. IO: the trusted shell.
#
# Trusted, not proved: `episteme ingest git` reads its cursor with
# `Store.cursor("git")` (laws/GitRecordFields.bend). Its repos are the entries
# of the root `$EPISTEME_PROJECTS` or `~/projects`, then of `<root>/bend`,
# each in name order, that hold a `.git` directory (a linked worktree or
# submodule, whose `.git` is a file, repeats another repo's history and is
# skipped); a repo `<root>/<x>` or `<root>/bend/<x>` is named `<x>`, its
# source `git:<x>`. It runs only read-only git commands, each as `git
# --no-lazy-fetch -C <path> ...` through Base's `Process.run` with up to 256
# MiB of output and a 600000 ms timeout, so a partial clone never fetches. For
# each repo it runs `log` with `Git.args(path, tips)`, `tips` the cursor's for
# the path (none when it lists the path not), and gives `Git.records(name,
# path, commits)` of `Git.read(out)`, each bad piece named on stderr by its
# first line. When the read gave commits, the last of them is `HEAD` as the
# read saw it, and the repo's tips become: that commit alone when there were
# none; else that commit and the old tips, less those the repo no longer holds
# (`rev-list --no-walk --ignore-missing`), reduced to those no other of them
# reaches (`merge-base --independent`), so the tips are at most the branch
# tips read and not merged since, and a tip rewritten away (an amend, a
# rebase) stays one until git prunes it; when either command fails, that
# commit and every old tip. When the read gave none, the tips stay. So a
# commit is read once: a branch read, then another, then the first again reads
# nothing the second time on the first; a rebase, amend or force-push reads
# only its new commits, whether or not the old tip still exists; a repo made
# again with another history is read whole. A read that fails (no exit 0) is
# reported on stderr with git's message and the repo is skipped, its tips left
# as they were; an empty repo reads as no commits. A shallow clone's history
# is read down to its shallow boundary: commits a later fetch deepens below
# the boundary are never read, since a tip already reaches them, and the
# boundary commit's numstat lists every file of its tree as added. Repos are
# gathered whole, in that order, until their records reach `Git.budget()`
# (4,000,000) code points of shard size, and then appended with one
# `Ingest.run`, whose batch carries the cursor with every gathered repo's
# tips; the rest go in one last `Ingest.run`. It prints each batch's count and
# the total records, commits read and repos. Two repos of one name share one
# source.
#
# Why it is trusted: It reads directories and runs `git`, which no law
# reaches; what git log's text becomes is laws/GitRecordFields.bend,
# laws/GitCutLosesNoLine.bend, laws/GitCutFits.bend and
# laws/GitMoreCountsDropped.bend, and which commits a revision list names,
# which hashes `rev-list --no-walk --ignore-missing` keeps and which
# `merge-base --independent` gives, is git's. `tests/smoke.sh` builds
# synthetic repos with `tests/fixtures/git/make.sh`: the record count over a
# repo and a nested one, a directory that is no repo and a linked worktree
# skipped, author times with UTC offsets read as UTC, a binary file's numstat
# line, the pointer that `show` resolves to the commit's patch, a second run
# that reads nothing, a new commit read once, an amended commit read once, a
# branch read and then main again reading nothing, a rewritten commit whose
# old tip was pruned read alone, a message holding U+001E read, a repo made
# again read whole with nothing on stderr, and no id twice.
import Base
import ../record.bend as R
import ../chat.bend as C
import ../git.bend as G
import ../store.bend as St
import ../ingest.bend as In
import ezsys@0.1.0.0/main.bend as Sys

# how far a run got: the cursor, the records read and not yet appended
# (newest repo first), their code points, the records appended, the
# commits read and the repos read so far
type Run is Data:
  Run{pos: List<&2, G.Pos>, recs: List<&2, List<&2, R.Record>>,
    chars: Nat, total: U32, commits: U32, repos: U32}

# a repo: its source name and its path
type Repo is Data:
  Repo{name: String, path: String}

# the code points of records a batch gathers before it is appended
def Git.budget() -> Nat:
  4000000n

# --- the repos ---

# a directory's names, or none when it cannot be read
def Git.names(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    res : Result<&1, &1, U32 & String, List<&2, String>> <- Sys.dir.list(path)
    return Result.default(&1, &1, U32 & String, List<&2, String>, res, [])

# the repo ahead of rest when its directory holds a .git directory
def Git.repo.if(has: Bool, +name: String, +path: String, rest: List<&2, Repo>) -> List<&2, Repo>:
  match has:
    case True{}:
      Repo{name, path} <> rest
    case False{}:
      rest

# the repos among the names of a directory, in order: a .git that lists
# as a directory (a repo's own; a linked worktree's or submodule's .git
# is a file, so it repeats another repo's history and is skipped)
def Git.repos(names: List<&2, String>, +dir: String) -> IO(List<&2, Repo>):
  match names:
    case Nil{}:
      IO.pure(List<&2, Repo>, [])
    case Con{+name, rest}:
      do IO<List<&2, Repo>>:
        +path : String = dir ++ "/" ++ name
        inside : List<&2, String> <- Git.names(path ++ "/.git")
        more : List<&2, Repo> <- Git.repos(rest, dir)
        return Git.repo.if(Bool.not(List.is_empty(&2, String, inside)), name, path, more)

# --- one repo ---

# git with the arguments, up to 256 MiB of output and ten minutes
def Git.git(args: List<&1, String>) -> IO(Result<&1, &1, U32 & String, U32 & (String & String)>):
  Process.run("git", args, "", 268435456, 600000)

# the output of a git command that exited 0, else None, said on stderr
def Git.out.if(ok: Bool, out: String, +err: String, +path: String) -> IO(Maybe<&2, String>):
  match ok:
    case True{}:
      IO.pure(Maybe<&2, String>, Some{out})
    case False{}:
      do IO<Maybe<&2, String>>:
        IO.print_err("episteme: git in " ++ path ++ ": " ++ String.trim(err))
        return None{}

# the output of a git command, or None, said on stderr, when it failed
def Git.out(res: Result<&1, &1, U32 & String, U32 & (String & String)>, +path: String) -> IO(Maybe<&2, String>):
  match res:
    case Fail{(_code, why)}:
      do IO<Maybe<&2, String>>:
        IO.print_err("episteme: git in " ++ path ++ ": " ++ why)
        return None{}
    case Done{(code, (out, err))}:
      Git.out.if(U32.is_eq(code, 0), out, err, path)

# the first line of a text
def Git.first(lines: List<&2, String>) -> String:
  match lines:
    case Nil{}:
      ""
    case Con{line, _rest}:
      line

# say each piece of git log's output that is no commit on stderr, by its
# first line
def Git.bad(pieces: List<&2, String>, +name: String) -> IO(Unit):
  match pieces:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{piece, rest}:
      do IO<Unit>:
        IO.print_err("episteme: git:" ++ name ++ ": git log gave no commit here: "
          ++ String.take(Git.first(String.lines(piece)), 80n))
        Git.bad(rest, name)

# the tips found, or every candidate when none was
def Git.tips.some(found: List<&2, String>, cands: List<&2, String>) -> List<&2, String>:
  match found:
    case Nil{}:
      cands
    case Con{tip, rest}:
      tip <> rest

# the independent commits merge-base found, or every candidate when git
# could not tell
def Git.tips.got(got: Maybe<&2, String>, cands: List<&2, String>) -> List<&2, String>:
  match got:
    case None{}:
      cands
    case Some{text}:
      Git.tips.some(G.Git.hashes(text), cands)

# the candidates the repo still holds reduced to those no other reaches;
# every candidate when git could not tell
def Git.tips.alive(got: Maybe<&2, String>, +path: String, +cands: List<&2, String>) -> IO(List<&2, String>):
  match got:
    case None{}:
      IO.pure(List<&2, String>, cands)
    case Some{text}:
      do IO<List<&2, String>>:
        res : Result<&1, &1, U32 & String, U32 & (String & String)> <-
          Git.git(G.Git.tips.args(path, G.Git.hashes(text)))
        got : Maybe<&2, String> <- Git.out(res, path)
        return Git.tips.got(got, cands)

# the tips after a read whose last commit, HEAD as the read saw it, is
# head: head alone when none were read before; else head and the old tips
# the repo still holds (rev-list --no-walk --ignore-missing), reduced to
# those no other reaches (merge-base --independent)
def Git.tips(+path: String, +head: String, old: List<&2, String>) -> IO(List<&2, String>):
  match old:
    case Nil{}:
      IO.pure(List<&2, String>, [head])
    case Con{tip, rest}:
      do IO<List<&2, String>>:
        +cands : List<&2, String> = head <> tip <> rest
        res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Git.git(G.Git.alive.args(path, cands))
        got : Maybe<&2, String> <- Git.out(res, path)
        Git.tips.alive(got, path, cands)

# the new tips when a read gave a last commit, else None
def Git.next(last: Maybe<&2, String>, +path: String, old: List<&2, String>) -> IO(Maybe<&2, List<&2, String>>):
  match last:
    case None{}:
      IO.pure(Maybe<&2, List<&2, String>>, None{})
    case Some{head}:
      do IO<Maybe<&2, List<&2, String>>>:
        tips : List<&2, String> <- Git.tips(path, head, old)
        return Some{tips}

# the records gathered, oldest repo first
def Git.gathered(recs: List<&2, List<&2, R.Record>>) -> List<&2, R.Record>:
  List.concat(&2, R.Record, List.reverse(&2, List<&2, R.Record>, recs))

# print how many records a batch appended, when it appended any
def Git.said(none: Bool, num: U32) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.print("git: " ++ U32.show(num) ++ " records appended")

# append the records gathered as one batch with the cursor; the run after
def Git.flush(run: Run) -> IO(Run):
  match run:
    case Run{+pos, recs, _chars, total, commits, repos}:
      do IO<Run>:
        +n : U32 <- In.Ingest.run("git", Git.gathered(recs), G.Git.cursor.text(pos))
        Git.said(U32.is_eq(n, 0), n)
        return Run{pos, [], 0n, U32.add(total, n), commits, repos}

# the run, flushed when its records reach the budget
def Git.flush.if(full: Bool, run: Run) -> IO(Run):
  match full:
    case True{}:
      Git.flush(run)
    case False{}:
      IO.pure(Run, run)

# the run after a repo's log: its bad pieces said, its commits' records
# gathered and its tips set in the cursor
def Git.take(run: Run, +repo: Repo, old: List<&2, String>, log: G.Log) -> IO(Run):
  match run repo log:
    case Run{pos, got, chars, total, commits, repos} Repo{+name, +path} G.Log{+cs, bad}:
      do IO<Run>:
        Git.bad(bad, name)
        tips : Maybe<&2, List<&2, String>> <- Git.next(G.Git.last(cs), path, old)
        +recs : List<&2, R.Record> = G.Git.records(name, path, cs)
        +more : Nat = Nat.add(chars, C.Chat.chars(recs))
        Git.flush.if(Nat.is_le(Git.budget(), more),
          Run{G.Git.cursor.put(pos, path, tips), recs <> got, more, total,
            U32.add(commits, U32.from_nat(List.length(&2, G.Commit, cs))), U32.inc(repos)})

# the run after a repo's read, unchanged when it failed
def Git.read(got: Maybe<&2, String>, old: List<&2, String>, run: Run, +repo: Repo) -> IO(Run):
  match got:
    case None{}:
      IO.pure(Run, run)
    case Some{text}:
      Git.take(run, repo, old, G.Git.read(text))

# the run after a repo: the commits HEAD reaches and none of the cursor's
# tips for it does; all of HEAD when it lists none
def Git.repo(run: Run, +repo: Repo) -> IO(Run):
  match run repo:
    case Run{+pos, recs, chars, total, commits, repos} Repo{+name, +path}:
      do IO<Run>:
        +old : List<&2, String> = G.Git.cursor.get(pos, path)
        res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Git.git(G.Git.args(path, old))
        got : Maybe<&2, String> <- Git.out(res, path)
        Git.read(got, old, Run{pos, recs, chars, total, commits, repos}, Repo{name, path})

# the run after each repo, in order
def Git.each(rs: List<&2, Repo>, run: Run) -> IO(Run):
  match rs:
    case Nil{}:
      IO.pure(Run, run)
    case Con{+repo, rest}:
      do IO<Run>:
        next : Run <- Git.repo(run, repo)
        Git.each(rest, next)

# print a run's total
def Git.done(run: Run) -> IO(Unit):
  match run:
    case Run{_pos, _recs, _chars, total, commits, repos}:
      IO.print("git: " ++ U32.show(total) ++ " records, " ++ U32.show(commits)
        ++ " commits read, " ++ U32.show(repos) ++ " repos")

# the root of the repos: $EPISTEME_PROJECTS, or ~/projects
def Git.root() -> IO(String):
  do IO<String>:
    home : String <- Sys.env.or("HOME", "")
    Sys.env.or("EPISTEME_PROJECTS", home ++ "/projects")

# ingest every commit not yet read, in batches of whole repos; prints each
# batch's count, then the total
def Git.run() -> IO(Unit):
  do IO<Unit>:
    +root : String <- Git.root()
    cursor : String <- St.Store.cursor("git")
    top : List<&2, String> <- Git.names(root)
    nested : List<&2, String> <- Git.names(root ++ "/bend")
    outer : List<&2, Repo> <- Git.repos(top, root)
    inner : List<&2, Repo> <- Git.repos(nested, root ++ "/bend")
    run : Run <- Git.each(List.append(&2, Repo, outer, inner), Run{G.Git.cursor(cursor), [], 0n, 0, 0, 0})
    last : Run <- Git.flush(run)
    Git.done(last)
