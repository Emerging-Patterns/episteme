# For dropped lines `rest` that are not empty, `Git.more(rest)` is the one
# line `<length(rest)> more files`.
import Base
import ../src/git.bend as G

# LAW: the line naming dropped lines names how many there are
law git_more:
  for line: String
  for more: List<&2, String>
  {G.Git.more(line <> more)
    == [Nat.show(List.length(&2, String, line <> more)) ++ " more files"] : List<&2, String>}
