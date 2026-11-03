import Base
import ../src/git.bend as G

# LAW: an example: UTC times of the epoch, a leap day, a year's last second
# and the last second a U32 holds
law git_utc_example:
  for u: Unit
  {[G.Git.utc(0), G.Git.utc(951782400), G.Git.utc(1767225599), G.Git.utc(4294967295)]
    == ["1970-01-01T00:00:00.000Z", "2000-02-29T00:00:00.000Z", "2025-12-31T23:59:59.000Z",
      "2106-02-07T06:28:15.000Z"] : List<&2, String>}
