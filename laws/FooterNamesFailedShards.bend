import Base
import ../src/read.bend as Rd

# LAW: an example: the footer of a run of two reads, one failed, named by
# its source and its own number in that source.
law footer_example:
  for u: Unit
  {Rd.Read.footer([Rd.Read{1, "http://a", ["p1"], True{}, "", 10, 20, 0, 30},
      Rd.Read.fail(2, "http://b", "HTTP 400: too long")],
      [Rd.Name{"book:a", 4}, Rd.Name{"chat:claude/x", 7}], 3, 12345n)
    == "shards: 2 read, 1 failed\nfailed chat:claude/x shard 7 at http://b: HTTP 400: too long\nunknown labels: 3\nwall time: 12.3 s"
    : String}
