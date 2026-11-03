# `Git.cut` loses and reorders no numstat line: for every `lines` and `left`,
# the lines `Git.cut(lines, left)` keeps, followed by those it drops, are
# `lines`.
import Base
import ../src/git.bend as G

# the lines a cut keeps, then those it drops
def git.joined(cut: G.Kept) -> List<&2, String>:
  match cut:
    case G.Kept{kept, rest}:
      List.append(&2, String, kept, rest)

# LAW: a cut loses and reorders no line: the lines kept, then those
# dropped, are the lines
law git_cut:
  for lines: List<&2, String>
  for left: Nat
  {git.joined(G.Git.cut(lines, left)) == lines : List<&2, String>}
