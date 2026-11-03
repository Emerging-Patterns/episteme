# which sources a filter's selectors select
import Base
import ../../src/filter.bend as F

# True when sel selects the source src: src equals an exact selector, or
# starts with a prefix selector
def selects(sel: F.Sel, +src: String) -> Bool:
  match sel:
    case F.Exact{text}:
      String.eq(src, text)
    case F.Prefix{text}:
      String.starts_with(src, text)

# True when some selector of sels selects the source src
def picked(+sels: List<&2, F.Sel>, +src: String) -> Bool:
  match sels:
    case Nil{}:
      False{}
    case Con{sel, rest}:
      Bool.or(selects(sel, src), picked(rest, src))

# True when sels selects some source of srcs
def overlaps(+sels: List<&2, F.Sel>, srcs: List<&2, String>) -> Bool:
  match srcs:
    case Nil{}:
      False{}
    case Con{src, rest}:
      Bool.or(picked(sels, src), overlaps(sels, rest))
