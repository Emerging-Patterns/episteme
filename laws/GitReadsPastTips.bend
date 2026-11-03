import Base
import ../src/chat.bend as C
import ../src/honcho.bend as H
import ../src/git.bend as G

# LAW: an example: a read takes the commits HEAD reaches and no tip does,
# with no lazy fetch and missing tips ignored
law git_args_example:
  for u: Unit
  {(G.Git.args("/r", ["a", "b"]), G.Git.args("/r", []))
    == (["--no-lazy-fetch", "-C", "/r", "log", "--reverse",
        "--format=%x00%H%x1f%at%x1f%an%x1f%B%x1f", "--numstat", "--ignore-missing",
        "--end-of-options", "HEAD", "^a", "^b"],
      ["--no-lazy-fetch", "-C", "/r", "log", "--reverse",
        "--format=%x00%H%x1f%at%x1f%an%x1f%B%x1f", "--numstat", "--ignore-missing",
        "--end-of-options", "HEAD"])
    : List<&1, String> & List<&1, String>}
