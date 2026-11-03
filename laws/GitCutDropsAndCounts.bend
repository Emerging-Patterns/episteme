import Base
import ../src/git.bend as G

# LAW: an example: a cut keeps lines while each with its line feed fits,
# then drops the rest, which the body counts
law git_cut_example:
  for u: Unit
  {(G.Git.cut(["ab", "cd", "e", "f"], 6n), G.Git.list(G.Git.cut(["ab", "cd", "e", "f"], 6n)),
      G.Git.list(G.Git.cut([], 6n)))
    == (G.Kept{["ab", "cd"], ["e", "f"]}, "\n\nfiles:\nab\ncd\n2 more files", "")
    : G.Kept & String & String}
