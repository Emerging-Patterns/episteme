# the words the laws on current records are stated in: the first record
# with an id, a list without an id, and what records must be for their
# shards to give them back
import Base
import ../../src/record.bend as R
import ../../src/live.bend as L
import ./Specification.bend as D1

# x when it has the id, else the first of the rest with it
def first.if(hit: Bool, rec: R.Record, rest: Maybe<&2, R.Record>) -> Maybe<&2, R.Record>:
  match hit:
    case True{}:
      Some{rec}
    case False{}:
      rest

# the first record of xs with the id, or none
def first(+id: String, xs: List<&2, R.Record>) -> Maybe<&2, R.Record>:
  match xs:
    case Nil{}:
      None{}
    case Con{+x, rest}:
      first.if(String.eq(L.Live.id(x), id), x, first(id, rest))

# x ahead of rest unless it has the id
def without.if(hit: Bool, rec: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match hit:
    case True{}:
      rest
    case False{}:
      rec <> rest

# the records of xs whose id is not id, in order
def without(+id: String, xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      without.if(String.eq(id, L.Live.id(x)), x, without(id, rest))

# nothing for a removal, else the record alone
def alone.if(gone: Bool, rec: R.Record) -> List<&2, R.Record>:
  match gone:
    case True{}:
      []
    case False{}:
      [rec]

# a record alone, or nothing when it is a removal
def alone(+rec: R.Record) -> List<&2, R.Record>:
  alone.if(L.Live.gone(rec), rec)

# True when no record of xs has the id of a record of ys
def fresh(xs: List<&2, R.Record>, +ys: List<&2, R.Record>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{x, rest}:
      Bool.and(Bool.not(L.Live.has(L.Live.id(x), ys)), fresh(rest, ys))

# every record of xs has a paragraph
def filled(xs: List<&2, R.Record>) -> Type:
  match xs:
    case Nil{}:
      Unit
    case Con{x, rest}:
      Pair({D1.full(D1.rec.paras(x)) == True{} : Bool}, filled(rest))

# True when no record of xs has the id of the one before it, the first
# not that of last
def apart(xs: List<&2, R.Record>, last: Maybe<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+x, rest}:
      Bool.and(Bool.not(L.Live.same(last, L.Live.id(x))), apart(rest, Some{L.Live.id(x)}))
