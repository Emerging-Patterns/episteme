# whether some excerpt holds a record id
import Base
import ../../src/excerpt.bend as E
import ../../laws/defs/Specification.bend as D1

# True when some excerpt of xs has the record id id
def ids(+id: String, xs: List<&2, E.Ex>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, tail}:
      Bool.or(String.eq(D1.rec.id(D1.ex.rec(x)), id), ids(id, tail))
