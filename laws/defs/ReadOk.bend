# whether a read answered
import Base
import ../../src/read.bend as Rd

# whether a read is ok
def read.ok(rd: Rd.Read) -> Bool:
  match rd:
    case Rd.Read{_shard, _inst, _labels, ok, _why, _pn, _pm, _cn, _ms}:
      ok
