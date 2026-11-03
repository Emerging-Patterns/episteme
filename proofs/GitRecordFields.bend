# proofs of laws/GitRecordFields.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C
import ../src/git.bend as G
import ../laws/GitRecordFields.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ./lemmas/OrElse.bend as M1

def Laws.git_record(_name, _path, _hash, _secs, _author, _msg, _files):
  {==}

# a record of a made record ahead of rest is the made one, from source with
# no thread and no parent, or one of rest
def git_made(
  -id: String,
  -ts: String,
  -source: String,
  -author: String,
  ps: List<&2, P.Para>,
  -ptr: String,
  -r: R.Record,
  -rest: List<&2, R.Record>,
  h: D1.Elem(R.Record, r, C.Chat.put(R.Record.make.go(id, ts, source, author, "", "", ps, ptr), rest))
) -> Or({Laws.git.stamp(r) == (source, "", "") : String & String & String},
  D1.Elem(R.Record, r, rest)):
  match ps:
    case Nil{}:
      Inr{h}
    case Con{p, more}:
      match h:
        case Inl{e}:
          Inl{%Equal.sym(R.Record, r,
              R.Record{id, ts, source, author, "", "", p <> more, ptr}, e)
            : {Laws.git.stamp(_) == (source, "", "") : String & String & String}
            {==}}
        case Inr{hr}:
          Inr{hr}

# every record of a repo's commits is from git:<name>, with no thread and
# no parent
def git_stamp(
  +name: String,
  +path: String,
  cs: List<&2, G.Commit>,
  -r: R.Record,
  h: D1.Elem(R.Record, r, G.Git.records(name, path, cs))
) -> {Laws.git.stamp(r) == ("git:" ++ name, "", "") : String & String & String}:
  match cs:
    case Nil{}:
      Empty.absurd({Laws.git.stamp(r) == ("git:" ++ name, "", "") : String & String & String}, h)
    case Con{c, rest}:
      match c:
        case G.Commit{hash, secs, author, msg, files}:
          M1.or_else({Laws.git.stamp(r) == ("git:" ++ name, "", "") : String & String & String},
            D1.Elem(R.Record, r, G.Git.records(name, path, rest)),
            git_made("git:" ++ name ++ "@" ++ hash, G.Git.utc(secs), "git:" ++ name, author,
              P.Para.split(G.Git.body(msg, files)), "git:" ++ path ++ "@" ++ hash, r,
              G.Git.records(name, path, rest), h),
            hr => git_stamp(name, path, rest, r, hr))

def Laws.git_stamp(name, path, cs, r, h):
  git_stamp(name, path, cs, r, h)
