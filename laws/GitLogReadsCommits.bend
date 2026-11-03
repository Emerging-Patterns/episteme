import Base
import ../src/excerpt.bend as E
import ../src/git.bend as G

# the separator git log writes before each commit, as text
def git.rs() -> String:
  String.from_list([G.Git.rs()])

# the separator git log writes after each field, as text
def git.us() -> String:
  String.from_list([G.Git.us()])

# U+001E, which a commit message may hold, as text
def git.x1e() -> String:
  String.from_list([Char.from_u32(30)])

# LAW: an example: a log text read to its commits: the blank text before
# the first separator is nothing, a message holding U+001E or a field
# separator keeps it, a commit with no files has none, and a piece whose
# time is not a number is a bad piece
law git_log_example:
  for u: Unit
  {G.Git.read(git.rs() ++ "h1" ++ git.us() ++ "1767213000" ++ git.us() ++ "Ann"
      ++ git.us() ++ "One\n\nTw" ++ git.x1e() ++ "o\n" ++ git.us()
      ++ "\n\n1\t0\ta.txt\n-\t-\tb.bin\n"
      ++ git.rs() ++ "h2" ++ git.us() ++ "60" ++ git.us() ++ "Bo" ++ git.us() ++ "a"
      ++ git.us() ++ "b\n" ++ git.us() ++ "\n" ++ git.rs() ++ "h3" ++ git.us() ++ "soon"
      ++ git.us() ++ "Cy" ++ git.us() ++ "c\n" ++ git.us() ++ "\n")
    == G.Log{[G.Commit{"h1", 1767213000, "Ann", "One\n\nTw" ++ git.x1e() ++ "o\n",
        ["1\t0\ta.txt", "-\t-\tb.bin"]},
      G.Commit{"h2", 60, "Bo", "a" ++ git.us() ++ "b\n", []}],
      ["h3" ++ git.us() ++ "soon" ++ git.us() ++ "Cy" ++ git.us() ++ "c\n" ++ git.us() ++ "\n"]}
    : G.Log}
