# proofs of laws/GitCutLosesNoLine.bend
import Base
import ../src/git.bend as G
import ../laws/GitCutLosesNoLine.bend as Laws

# the lines of a cut with a line kept ahead are that line ahead of its lines
def git_keep(
  -line: String,
  cut: G.Kept
) -> {Laws.git.joined(G.Git.keep(line, cut)) == line <> Laws.git.joined(cut) : List<&2, String>}:
  match cut:
    case G.Kept{_kept, _rest}:
      {==}

# one step of a cut loses and reorders no line, when the rest of the cut
# does not
def git_cut.step(
  b: Bool,
  +line: String,
  -rest: List<&2, String>,
  more: Unit -> G.Kept,
  ih: {Laws.git.joined(more(Unit{})) == rest : List<&2, String>}
) -> {Laws.git.joined(G.Git.cut.if(b, line, rest, more)) == line <> rest : List<&2, String>}:
  match b:
    case True{}:
      Equal.trans(List<&2, String>, Laws.git.joined(G.Git.keep(line, more(Unit{}))),
        line <> Laws.git.joined(more(Unit{})), line <> rest,
        git_keep(line, more(Unit{})),
        Equal.cong(List<&2, String>, List<&2, String>, ys => line <> ys,
          Laws.git.joined(more(Unit{})), rest, ih))
    case False{}:
      {==}

# a cut loses and reorders no line
def git_cut(
  lines: List<&2, String>,
  +left: Nat
) -> {Laws.git.joined(G.Git.cut(lines, left)) == lines : List<&2, String>}:
  match lines:
    case Nil{}:
      {==}
    case Con{+line, +rest}:
      git_cut.step(Nat.is_le(Nat.add(String.length(line), 1n), left), line, rest,
        _u => G.Git.cut(rest, Nat.sub(left, Nat.add(String.length(line), 1n))),
        git_cut(rest, Nat.sub(left, Nat.add(String.length(line), 1n))))

def Laws.git_cut(lines, left):
  git_cut(lines, left)
