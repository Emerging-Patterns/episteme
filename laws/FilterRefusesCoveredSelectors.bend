# `Filter.check(refs, f)` refuses the empty filter with `Filter.required()`,
# refuses a filter holding a selector that selects every source some
# refused selector selects, with that refusal's message, and passes every
# other filter.
#
# The refusals are the store's to set (`config.json`'s `refuse`, each
# `[selector, message]`, read as `Filter.parse` reads a piece:
# `Filter.refusal(text, why)`), so a setup can refuse filters that would
# read too much of the record, and episteme names no source in them. A
# selector covers a refused one (`Filter.covers(r, sel)`) when it selects
# every source the refused one does: the same exact source, or a prefix of
# the refused selector's text (a prefix of an exact source's name or of a
# refused prefix). So refusing a prefix also refuses every shorter prefix
# of it, the empty prefix among them, and leaves longer ones, which name
# less, alone. The first selector of the filter that some refusal covers
# gives the message, the first such refusal's (`Filter.why`,
# `Filter.whys`). Closed examples check a refused prefix, a refused exact
# source, a shorter prefix, a longer one, a source not refused and a store
# that refuses nothing.
import Base
import ../src/filter.bend as F

# LAW: the empty filter is refused, whatever the store refuses
law check_empty:
  for refs: List<&2, F.Refusal>
  {F.Filter.check(refs, []) == Fail{F.Filter.required()}
    : Result<&2, &2, String, Unit>}

# LAW: a filter some refusal covers is refused with its message
law check_refused:
  for refs: List<&2, F.Refusal>
  for sel: F.Sel
  for rest: List<&2, F.Sel>
  for why: String
  for h: {F.Filter.whys(refs, sel <> rest) == Some{why} : Maybe<&2, String>}
  {F.Filter.check(refs, sel <> rest) == Fail{why}
    : Result<&2, &2, String, Unit>}

# LAW: a non-empty filter no refusal covers passes
law check_passes:
  for refs: List<&2, F.Refusal>
  for sel: F.Sel
  for rest: List<&2, F.Sel>
  for h: {F.Filter.whys(refs, sel <> rest) == None{} : Maybe<&2, String>}
  {F.Filter.check(refs, sel <> rest) == Done{Unit{}}
    : Result<&2, &2, String, Unit>}

# LAW: the first refusal a selector covers gives its message
law why_first:
  for r: F.Sel
  for why: String
  for rest: List<&2, F.Refusal>
  for sel: F.Sel
  for h: {F.Filter.covers(r, sel) == True{} : Bool}
  {F.Filter.why(F.Refusal{r, why} <> rest, sel) == Some{why}
    : Maybe<&2, String>}

# LAW: a refusal the selector does not cover is passed over
law why_skips:
  for r: F.Sel
  for why: String
  for rest: List<&2, F.Refusal>
  for sel: F.Sel
  for h: {F.Filter.covers(r, sel) == False{} : Bool}
  {F.Filter.why(F.Refusal{r, why} <> rest, sel) == F.Filter.why(rest, sel)
    : Maybe<&2, String>}

# LAW: no refusal, no message
law why_none:
  for sel: F.Sel
  {F.Filter.why([], sel) == None{} : Maybe<&2, String>}

# LAW: the filter's message is its first selector's, else the rest's
law whys_first:
  for refs: List<&2, F.Refusal>
  for sel: F.Sel
  for rest: List<&2, F.Sel>
  {F.Filter.whys(refs, sel <> rest)
    == Maybe.or(&2, String, F.Filter.why(refs, sel), F.Filter.whys(refs, rest))
    : Maybe<&2, String>}

# LAW: an exact selector covers only the same exact source
law covers_exact:
  for t: String
  for s: String
  {F.Filter.covers(F.Exact{t}, F.Exact{s}) == String.eq(s, t) : Bool}

# LAW: a prefix covers an exact source its text starts
law covers_exact_by_prefix:
  for t: String
  for p: String
  {F.Filter.covers(F.Exact{t}, F.Prefix{p}) == String.starts_with(t, p) : Bool}

# LAW: a prefix covers a prefix whose text it starts
law covers_prefix:
  for t: String
  for p: String
  {F.Filter.covers(F.Prefix{t}, F.Prefix{p}) == String.starts_with(t, p) : Bool}

# LAW: an exact selector never covers a refused prefix
law covers_no_prefix_by_exact:
  for t: String
  for s: String
  {F.Filter.covers(F.Prefix{t}, F.Exact{s}) == False{} : Bool}

# the refusals the examples set
def refs() -> List<&2, F.Refusal>:
  [F.Filter.refusal("notes:all", "name one notebook"),
   F.Filter.refusal("notes:all/", "name one notebook's prefix")]

# LAW: an example: the refused prefix is refused with its message
law refused_prefix_example:
  for u: Unit
  {F.Filter.check(refs(), F.Filter.parse(["notes:all/"]))
    == Fail{"name one notebook's prefix"} : Result<&2, &2, String, Unit>}

# LAW: an example: the refused exact source is refused with its message
law refused_exact_example:
  for u: Unit
  {F.Filter.check(refs(), F.Filter.parse(["book:x/, notes:all"]))
    == Fail{"name one notebook"} : Result<&2, &2, String, Unit>}

# LAW: an example: a shorter prefix, and the empty one, are refused
law shorter_prefix_example:
  for u: Unit
  {[F.Filter.check(refs(), [F.Prefix{"notes:"}]), F.Filter.check(refs(), [F.Prefix{""}])]
    == [Fail{"name one notebook"}, Fail{"name one notebook"}]
    : List<&2, Result<&2, &2, String, Unit>>}

# LAW: an example: a longer prefix and another source pass
law longer_prefix_example:
  for u: Unit
  {[F.Filter.check(refs(), F.Filter.parse(["notes:all/one/"])),
    F.Filter.check(refs(), F.Filter.parse(["notes:other"]))]
    == [Done{Unit{}}, Done{Unit{}}] : List<&2, Result<&2, &2, String, Unit>>}

# LAW: an example: a store that refuses nothing passes any non-empty
# filter, and still refuses the empty one
law nothing_refused_example:
  for u: Unit
  {[F.Filter.check([], [F.Prefix{""}]), F.Filter.check([], F.Filter.parse([" , "]))]
    == [Done{Unit{}}, Fail{F.Filter.required()}]
    : List<&2, Result<&2, &2, String, Unit>>}
