# The lines `Git.cut(lines, left)` keeps, each with its line feed, take at
# most `left` code points, for every `lines` and `left`.
import Base
import ../src/git.bend as G

# the code points lines take, each with its line feed
def git.used(lines: List<&2, String>) -> Nat:
  match lines:
    case Nil{}:
      0n
    case Con{line, rest}:
      Nat.add(Nat.add(String.length(line), 1n), git.used(rest))

# the lines a cut keeps
def git.kept(cut: G.Kept) -> List<&2, String>:
  match cut:
    case G.Kept{kept, _rest}:
      kept

# LAW: the lines a cut keeps, each with its line feed, fit in what it was
# left
law git_fit:
  for lines: List<&2, String>
  for left: Nat
  {Nat.is_le(git.used(git.kept(G.Git.cut(lines, left))), left) == True{} : Bool}
