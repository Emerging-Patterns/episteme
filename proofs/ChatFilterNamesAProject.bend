# proofs of laws/ChatFilterNamesAProject.bend
import Base
import ../src/filter.bend as F
import ../laws/ChatFilterNamesAProject.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/OffsetsHeld.bend as M1

# the code's chat-wide test is the specification's
law wide_eq:
  for sel: F.Sel
  {F.Filter.wide(sel) == D1.chat_wide(sel) : Bool}

def wide_eq(sel):
  match sel:
    case F.Exact{_t}:
      {==}
    case F.Prefix{_t}:
      {==}

# the code's test over the selectors is the specification's
law any_wide_eq:
  for sels: List<&2, F.Sel>
  {F.Filter.any_wide(sels) == D1.some_wide(sels) : Bool}

def any_wide_eq(sels):
  match sels:
    case Nil{}:
      {==}
    case Con{+sel, +rest}:
      %wide_eq(sel) : {List.any.if(_u => F.Filter.any_wide(rest),
        F.Filter.wide(sel))
        == Bool.or(_, D1.some_wide(rest)) : Bool}
      M1.any_if_or(F.Filter.wide(sel), F.Filter.any_wide(rest),
        D1.some_wide(rest), any_wide_eq(rest))

# the code's answer for a verdict is the specification's
law check_if_eq:
  for bad: Bool
  {F.Filter.check.if(bad) == Laws.verdict(bad)
    : Result<&2, &2, String, Unit>}

def check_if_eq(bad):
  match bad:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.filter_check(sels):
  match sels:
    case Nil{}:
      {==}
    case Con{+sel, +rest}:
      %any_wide_eq(sel <> rest) : {F.Filter.check.if(F.Filter.any_wide(sel
        <> rest)) == Laws.verdict(_) : Result<&2, &2, String, Unit>}
      check_if_eq(F.Filter.any_wide(sel <> rest))
