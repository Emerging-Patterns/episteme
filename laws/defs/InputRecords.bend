# the words the laws on records given as input are stated in
import Base
import ../../src/record.bend as R
import ../../src/live.bend as L
import ../../src/intake.bend as I

# h ahead of rest when keep
def lacking.if(keep: Bool, h: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match keep:
    case True{}:
      h <> rest
    case False{}:
      rest

# the records of held whose id no record of xs has, in order
def lacking(held: List<&2, R.Record>, +xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match held:
    case Nil{}:
      []
    case Con{+h, rest}:
      lacking.if(Bool.not(L.Live.has(L.Live.id(h), xs)), h, lacking(rest, xs))

# the removal of each record of hs, in order
def removals(hs: List<&2, R.Record>) -> List<&2, R.Record>:
  match hs:
    case Nil{}:
      []
    case Con{h, rest}:
      I.Intake.removal(h) <> removals(rest)
