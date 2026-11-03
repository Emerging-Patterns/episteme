# `Read.failed(rs)` is exactly the reads of `rs` that are not ok, in order,
# and `Read.code(rs)` is 1 when some read is not ok, else 0.
import Base
import ../src/read.bend as Rd
import ./defs/FrozenShards.bend as D1
import ./defs/ReadOk.bend as D2

# r alone when it failed, else nothing
def failing.one(ok: Bool, rd: Rd.Read) -> List<&2, Rd.Read>:
  match ok:
    case True{}:
      []
    case False{}:
      [rd]

# the reads of rs that failed, in order
def failing(rs: List<&2, Rd.Read>) -> List<&2, Rd.Read>:
  match rs:
    case Nil{}:
      []
    case Con{+r, rest}:
      List.append(&2, Rd.Read, failing.one(D2.read.ok(r), r), failing(rest))

# True when some read of rs failed
def any_failed(rs: List<&2, Rd.Read>) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case Con{r, rest}:
      Bool.or(Bool.not(D2.read.ok(r)), any_failed(rest))

# LAW: the failed reads the footer lists are exactly the reads that are
# not ok, in order
law failed_spec:
  for rs: List<&2, Rd.Read>
  {Rd.Read.failed(rs) == failing(rs) : List<&2, Rd.Read>}

# LAW: a run exits 1 when some read failed, else 0
law code_failed:
  for rs: List<&2, Rd.Read>
  {Rd.Read.code(rs) == D1.flag(any_failed(rs)) : U32}
