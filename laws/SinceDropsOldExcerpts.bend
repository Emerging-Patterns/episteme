# `Filter.after(Some{t}, xs)` keeps exactly the excerpts of `xs`, in order,
# whose record's `ts` is not before `t`: no excerpt whose `ts` is before `t`
# survives.
import Base
import ../src/filter.bend as F
import ../src/excerpt.bend as E
import ./defs/Specification.bend as D1

# the excerpts of xs, in order, whose record is at or after since
def kept_after(xs: List<&2, E.Ex>, +since: String) -> List<&2, E.Ex>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      List.filter.put(E.Ex, x, kept_after(rest, since), D1.at_or_after(D1.ex.ts(x), since))

# True when no excerpt of xs has a ts before since
def none_before(xs: List<&2, E.Ex>, +since: String) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{x, rest}:
      Bool.and(Bool.not(String.is_lt(D1.ex.ts(x), since)), none_before(rest, since))

# LAW: a since keeps exactly the excerpts at or after it, in order
law since_excerpts:
  for +since: String
  for xs: List<&2, E.Ex>
  {F.Filter.after(Some{since}, xs) == kept_after(xs, since) : List<&2, E.Ex>}

# LAW: no excerpt before the since survives
law since_none_old:
  for +since: String
  for xs: List<&2, E.Ex>
  {none_before(F.Filter.after(Some{since}, xs), since) == True{} : Bool}
