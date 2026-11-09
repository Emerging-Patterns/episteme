# episteme/src/git: a commit of `git log` read as a record, its files list
# capped, the arguments of the read, and the git connector's cursor.
# Pure: no IO.
import Base
import ./record.bend as R
import ./chat.bend as C
import ezsys@0.1.0.0/src/clock.bend as Clock

# a commit as git log gives it: its hash, its author time in seconds since
# 1970-01-01T00:00:00Z, its author's name, its message and its numstat
# lines
type Commit is Data:
  Commit{hash: String, secs: U32, author: String, msg: String,
    files: List<&2, String>}

# the numstat lines a record keeps, and those dropped after them
type Kept is Data:
  Kept{kept: List<&2, String>, rest: List<&2, String>}

# what git log's text reads as: its commits, in order, and the pieces that
# are no commit
type Log is Data:
  Log{commits: List<&2, Commit>, bad: List<&2, String>}

# one entry of the cursor: a repo's path and the tips read in it, every
# commit they reach read
type Pos is Data:
  Pos{repo: String, tips: List<&2, String>}

# --- reading git log ---

# the code point git log writes before each commit (%x00), which no
# commit message can hold
def Git.rs() -> Char:
  Char.from_u32(0)

# the code point git log writes after each field (%x1f)
def Git.us() -> Char:
  Char.from_u32(31)

# each tip as ^<tip>: a commit it reaches is not read
def Git.nots(tips: List<&2, String>) -> List<&1, String>:
  match tips:
    case Nil{}:
      []
    case Con{tip, rest}:
      ("^" ++ tip) <> Git.nots(rest)

# each hash, in order
def Git.revs(hashes: List<&2, String>) -> List<&1, String>:
  match hashes:
    case Nil{}:
      []
    case Con{hash, rest}:
      hash <> Git.revs(rest)

# the arguments of `git --no-lazy-fetch -C <repo> log`: the commits HEAD
# reaches and no tip does, oldest first, each as %x00, then hash, author
# time, author name and message, each followed by %x1f, then its numstat
# lines; a tip, or a HEAD, that is no commit is ignored; the revisions
# after --end-of-options, so none is read as an option
def Git.args(+repo: String, tips: List<&2, String>) -> List<&1, String>:
  List.append(&1, String,
    ["--no-lazy-fetch", "-C", repo, "log", "--reverse",
      "--format=%x00%H%x1f%at%x1f%an%x1f%B%x1f", "--numstat", "--ignore-missing",
      "--end-of-options", "HEAD"],
    Git.nots(tips))

# the arguments of `git --no-lazy-fetch -C <repo> rev-list --no-walk
# --ignore-missing`: which of the hashes are commits the repo holds
def Git.alive.args(+repo: String, hashes: List<&2, String>) -> List<&1, String>:
  List.append(&1, String,
    ["--no-lazy-fetch", "-C", repo, "rev-list", "--no-walk", "--ignore-missing",
      "--end-of-options"],
    Git.revs(hashes))

# the arguments of `git --no-lazy-fetch -C <repo> merge-base
# --independent`: the hashes no other of them reaches
def Git.tips.args(+repo: String, hashes: List<&2, String>) -> List<&1, String>:
  List.append(&1, String,
    ["--no-lazy-fetch", "-C", repo, "merge-base", "--independent", "--end-of-options"],
    Git.revs(hashes))

# rest, with line ahead of it unless the line is blank
def Git.files.if(blank: Bool, line: String, rest: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      rest
    case False{}:
      line <> rest

# the numstat lines of the text after a commit's last field: its lines
# that are not blank
def Git.files(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}:
      []
    case Con{+line, rest}:
      Git.files.if(String.is_empty(String.trim(line)), line, Git.files(rest))

# the hashes of a command's output, one a line; blank lines are none
def Git.hashes(text: String) -> List<&2, String>:
  Git.files(String.lines(text))

# the commit of its fields: the message is every field between the author
# and the last, joined again by %x1f; None when the time is not a number
# or a field is missing
def Git.commit.of(
  hash: String,
  secs: Maybe<&2, U32>,
  author: String,
  rev: List<&2, String>
) -> Maybe<&2, Commit>:
  match secs rev:
    case Some{s} Con{rest, Con{m, ms}}:
      Some{Commit{hash, s, author,
        String.join(List.reverse(&2, String, m <> ms), String.from_list([Git.us()])),
        Git.files(String.lines(rest))}}
    case _ _:
      None{}

# the commit of a piece's fields, or None when it has fewer than five
def Git.commit.fields(fields: List<&2, String>) -> Maybe<&2, Commit>:
  match fields:
    case Con{hash, Con{secs, Con{author, more}}}:
      Git.commit.of(hash, U32.read(secs), author, List.reverse(&2, String, more))
    case _:
      None{}

# the commit of the text git log writes after one %x00, or None when it
# is not one
def Git.commit(piece: String) -> Maybe<&2, Commit>:
  Git.commit.fields(String.split(piece, Git.us()))

# the bad pieces with piece ahead, unless it is blank
def Git.bad.put(blank: Bool, piece: String, rest: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      rest
    case False{}:
      piece <> rest

# the log with a piece's commit ahead, or the piece ahead of its bad pieces
# when it is no commit and not blank
def Git.piece.put(got: Maybe<&2, Commit>, +piece: String, log: Log) -> Log:
  match got log:
    case Some{commit} Log{commits, bad}:
      Log{commit <> commits, bad}
    case None{} Log{commits, bad}:
      Log{commits, Git.bad.put(String.is_empty(String.trim(piece)), piece, bad)}

# what pieces read as, in order
def Git.pieces(ps: List<&2, String>) -> Log:
  match ps:
    case Nil{}:
      Log{[], []}
    case Con{+piece, rest}:
      Git.piece.put(Git.commit(piece), piece, Git.pieces(rest))

# what git log's text reads as: the text cut at each %x00, each piece a
# commit or, when it is not blank (the text before the first %x00 is), a
# bad piece
def Git.read(text: String) -> Log:
  Git.pieces(String.split(text, Git.rs()))

# a log's commits
def Git.log.commits(log: Log) -> List<&2, Commit>:
  match log:
    case Log{commits, _bad}:
      commits

# the commits of git log's text, in order
def Git.commits(text: String) -> List<&2, Commit>:
  Git.log.commits(Git.read(text))

# a commit's hash
def Git.hash(commit: Commit) -> String:
  match commit:
    case Commit{hash, _secs, _author, _msg, _files}:
      hash

# the hash of the last commit, or None when there is none
def Git.last(cs: List<&2, Commit>) -> Maybe<&2, String>:
  match cs:
    case Nil{}:
      None{}
    case Con{commit, Nil{}}:
      Some{Git.hash(commit)}
    case Con{_c, Con{d, ds}}:
      Git.last(d <> ds)

# --- a commit's record ---

# the code points of numstat lines a record keeps, each with its line
# feed: about half a shard of the default size (41,779), so a commit that
# touches thousands of files stays one record that fits in a shard
def Git.files.max() -> Nat:
  20000n

# line kept ahead of what the rest keeps
def Git.keep(line: String, cut: Kept) -> Kept:
  match cut:
    case Kept{kept, rest}:
      Kept{line <> kept, rest}

# the line and what the rest keeps when the line fits, else nothing kept
# from the line on
def Git.cut.if(fits: Bool, line: String, rest: List<&2, String>, more: Unit -> Kept) -> Kept:
  match fits:
    case True{}:
      Git.keep(line, more(Unit{}))
    case False{}:
      Kept{[], line <> rest}

# the lines kept while they fit in left code points, each with its line
# feed, and the lines dropped from the first that does not fit on
def Git.cut(lines: List<&2, String>, +left: Nat) -> Kept:
  match lines:
    case Nil{}:
      Kept{[], []}
    case Con{+line, +rest}:
      +used : Nat = Nat.add(String.length(line), 1n)
      Git.cut.if(Nat.is_le(used, left), line, rest, _u => Git.cut(rest, Nat.sub(left, used)))

# the line naming how many lines were dropped, none when none were
def Git.more(rest: List<&2, String>) -> List<&2, String>:
  match rest:
    case Nil{}:
      []
    case Con{+line, more}:
      [Nat.show(List.length(&2, String, line <> more)) ++ " more files"]

# "files:" and the lines, after a blank line; nothing when there are none
def Git.listed(lines: List<&2, String>) -> String:
  match lines:
    case Nil{}:
      ""
    case Con{line, more}:
      "\n\nfiles:\n" ++ String.join(line <> more, "\n")

# the files part of a body: the lines kept, then how many were dropped
def Git.list(cut: Kept) -> String:
  match cut:
    case Kept{kept, rest}:
      Git.listed(List.append(&2, String, kept, Git.more(rest)))

# a commit's body: its message, then "files:" and its numstat lines, cut
# to Git.files.max() code points
def Git.body(msg: String, files: List<&2, String>) -> String:
  msg ++ Git.list(Git.cut(files, Git.files.max()))

# ISO 8601 UTC of seconds since 1970, `YYYY-MM-DDTHH:MM:SS.000Z`
def Git.utc(secs: U32) -> String:
  Clock.time.iso(secs, 0)

# the record of a commit of the repo named name at path: id
# git:<name>@<hash>, ts its author time in UTC, source git:<name>, its
# author, no thread or parent, the body Git.body, and the pointer
# git:<path>@<hash>; None when the body has no paragraph
def Git.record(+name: String, +path: String, commit: Commit) -> Maybe<&2, R.Record>:
  match commit:
    case Commit{+hash, secs, author, msg, files}:
      R.Record.make("git:" ++ name ++ "@" ++ hash, Git.utc(secs), "git:" ++ name,
        author, "", "", Git.body(msg, files), "git:" ++ path ++ "@" ++ hash)

# the records of commits of a repo, in order
def Git.records(+name: String, +path: String, cs: List<&2, Commit>) -> List<&2, R.Record>:
  match cs:
    case Nil{}:
      []
    case Con{commit, rest}:
      C.Chat.put(Git.record(name, path, commit), Git.records(name, path, rest))

# --- the cursor ---

# the tips of a cursor line's first field, split at spaces
def Git.tips(text: String) -> List<&2, String>:
  Git.files(String.split(text, ' '))

# a cursor entry of a repo and its tips, or None when either is empty
def Git.pos.of(+repo: String, tips: List<&2, String>) -> Maybe<&2, Pos>:
  match tips:
    case Nil{}:
      None{}
    case Con{tip, rest}:
      Bool.pick(Maybe<&2, Pos>, String.is_empty(repo), None{}, Some{Pos{repo, tip <> rest}})

# a cursor entry from its line "<tip> <tip>...\t<repo>", or None when it is
# not one; a line of one hash, as the first cursors wrote, is one tip
def Git.pos.line(+text: String) -> Maybe<&2, Pos>:
  Git.pos.of(C.Chat.after.tab(text), Git.tips(C.Chat.upto.tab(text)))

# the entry ahead of rest, when there is one
def Git.pos.put(got: Maybe<&2, Pos>, rest: List<&2, Pos>) -> List<&2, Pos>:
  match got:
    case None{}:
      rest
    case Some{pos}:
      pos <> rest

# cursor entries from its lines
def Git.pos.lines(lines: List<&2, String>) -> List<&2, Pos>:
  match lines:
    case Nil{}:
      []
    case Con{+text, rest}:
      Git.pos.put(Git.pos.line(text), Git.pos.lines(rest))

# the cursor's entries, one "<tip> <tip>...\t<repo>" line each; a line that
# is not one is dropped
def Git.cursor(text: String) -> List<&2, Pos>:
  Git.pos.lines(String.lines(text))

# the tips when hit, else what the rest says
def Git.cursor.get.if(hit: Bool, tips: List<&2, String>, rest: Unit -> List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      tips
    case False{}:
      rest(Unit{})

# the tips read in a repo, none when the cursor lists it not
def Git.cursor.get(ps: List<&2, Pos>, +repo: String) -> List<&2, String>:
  match ps:
    case Nil{}:
      []
    case Con{pos, rest}:
      match pos:
        case Pos{name, tips}:
          Git.cursor.get.if(String.eq(name, repo), tips, _u => Git.cursor.get(rest, repo))

# the entry with the new tips when hit, ahead of the rest set
def Git.cursor.set.if(
  hit: Bool,
  name: String,
  old: List<&2, String>,
  tips: List<&2, String>,
  rest: List<&2, Pos>,
  more: Unit -> List<&2, Pos>
) -> List<&2, Pos>:
  match hit:
    case True{}:
      Pos{name, tips} <> rest
    case False{}:
      Pos{name, old} <> more(Unit{})

# the cursor with a repo's tips set: its entry replaced in place, or a new
# entry at the end
def Git.cursor.set(ps: List<&2, Pos>, +repo: String, +tips: List<&2, String>) -> List<&2, Pos>:
  match ps:
    case Nil{}:
      [Pos{repo, tips}]
    case Con{pos, +rest}:
      match pos:
        case Pos{+name, old}:
          Git.cursor.set.if(String.eq(name, repo), name, old, tips, rest,
            _u => Git.cursor.set(rest, repo, tips))

# the cursor with a repo's tips set when a read gave some, else as it was
def Git.cursor.put(ps: List<&2, Pos>, +repo: String, got: Maybe<&2, List<&2, String>>) -> List<&2, Pos>:
  match got:
    case None{}:
      ps
    case Some{tips}:
      Git.cursor.set(ps, repo, tips)

# the cursor as text, one "<tip> <tip>...\t<repo>" line per entry
def Git.cursor.text(ps: List<&2, Pos>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{pos, rest}:
      match pos:
        case Pos{repo, tips}:
          String.join(tips, " ") ++ "\t" ++ repo ++ "\n" ++ Git.cursor.text(rest)
