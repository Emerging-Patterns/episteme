import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/git.bend as G

# LAW: an example: a commit's record, its author time in UTC and its files
# after its message
law git_record_example:
  for u: Unit
  {G.Git.records("fix", "/p/fix", [G.Commit{"h1", 1767213000, "Ann", "One\n", ["1\t0\ta.txt"]},
      G.Commit{"h2", 60, "Bo", "\n", []}])
    == [R.Record{"git:fix@h1", "2025-12-31T20:30:00.000Z", "git:fix", "Ann", "", "",
      [P.Para{1, 0, 3, "One"}, P.Para{2, 6, 22, "files:\n1\t0\ta.txt"}], "git:/p/fix@h1"}]
    : List<&2, R.Record>}
