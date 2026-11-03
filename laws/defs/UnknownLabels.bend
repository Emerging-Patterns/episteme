# how many of a reader's labels a shard does not have
import Base
import ../../src/excerpt.bend as E

# how many labels resolve counts as unknown
def unknown(got: List<&2, E.Ex> & U32) -> U32:
  match got:
    case (_xs, k):
      k
