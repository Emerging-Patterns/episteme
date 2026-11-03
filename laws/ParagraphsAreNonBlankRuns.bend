# Paragraphs are the maximal runs of non-blank lines, with blank-only runs
# dropped.
#
# `Para.split(text)` in `src/para.bend` cuts a text into numbered paragraphs,
# the unit a reader points at. A line is a run of code points up to a line
# feed or the end of the text; a line is blank when every code point of it is
# whitespace (`Char.is_space`). A paragraph's `start` and `end` are code-point
# offsets into the text, `end` exclusive, and its text is the slice between
# them, verbatim. Offsets are U32, so the laws that read offsets hold for
# every text shorter than 2^32 code points: their precondition is that the
# text's length survives a round trip through U32. `para_cover` proves that no
# non-whitespace code point is lost, `para_tiled` that the paragraphs are in
# order and disjoint with only whitespace around them, hold no blank line, and
# have a blank line between two of them unless the first was cut, and
# `para_cut` that every paragraph ends where its run ends, or at a line feed
# whose next line would not fit, or is a piece of exactly `Para.max()` code
# points with no line feed.
import Base
import ../src/para.bend as P
import ./defs/Specification.bend as D1

# LAW: no paragraph's text is all whitespace
law para_nonblank:
  for +text: String
  for p: P.Para
  for h: D1.In(p, P.Para.split(text))
  {D1.blank(D1.para.text(p)) == False{} : Bool}

# True when every line feed of str is followed by a line that holds a
# non-whitespace code point
def fedok(str: String) -> Bool:
  match str:
    case SNil{}:
      True{}
    case SCon{+head, +tail}:
      Bool.and(Bool.or(Bool.not(D1.nl(head)), Bool.not(D1.blank(D1.line(tail)))), fedok(tail))

# True when every line of str, split at its line feeds, the first and the
# last too, holds a non-whitespace code point: str holds no blank line and
# neither starts nor ends with a line feed
def lines_full(+str: String) -> Bool:
  Bool.and(Bool.not(D1.blank(D1.line(str))), fedok(str))

# the text after a paragraph starts with a blank line: a line feed, a
# whitespace line, and another line feed
def feedblank(text: String, pa: P.Para) -> Type:
  Exists(Char, head => Exists(String, rest =>
    Pair({D1.after(text, pa) == SCon{head, rest} : String},
    Pair({D1.nl(head) == True{} : Bool},
    Pair({D1.blank(D1.line(rest)) == True{} : Bool},
      {D1.nonl(rest) == False{} : Bool})))))

# between a paragraph and the next one, if any: a blank line, unless the
# paragraph was cut
def sep(text: String, pa: P.Para, ps: List<&2, P.Para>) -> Type:
  match ps:
    case Nil{}:
      Unit
    case Con{_next, _rest}:
      Or(feedblank(text, pa), Or(D1.cut_feed(text, pa), D1.cut_hard(pa)))

# from offset lo on, the text is the paragraphs ps in order, each after the
# one before, with only whitespace before, between and after them, every
# line of one holding a non-whitespace code point, and a blank line between
# two unless the first was cut
def tiled(+text: String, +lo: Nat, ps: List<&2, P.Para>) -> Type:
  match ps:
    case Nil{}:
      {D1.blank(String.drop(text, lo)) == True{} : Bool}
    case Con{+pa, +rest}:
      Pair({Nat.is_le(lo, U32.to_nat(D1.para.start(pa))) == True{} : Bool},
      Pair({D1.blank(D1.slice(text, lo, U32.to_nat(D1.para.start(pa)))) == True{} : Bool},
      Pair({Nat.is_le(U32.to_nat(D1.para.start(pa)), U32.to_nat(D1.para.end(pa)))
        == True{} : Bool},
      Pair({lines_full(D1.para.text(pa)) == True{} : Bool},
      Pair(sep(text, pa, rest), tiled(text, U32.to_nat(D1.para.end(pa)), rest))))))

# LAW: every non-whitespace code point of the text lies in some paragraph,
# for every text shorter than 2^32 code points
law para_cover:
  for +text: String
  for fits: {U32.to_nat(U32.from_nat(String.length(text)))
    == String.length(text) : Nat}
  for +i: Nat
  for c: Char
  for hc: {String.get(text, i) == Some{c} : Maybe<&2, Char>}
  for hs: {Char.is_space(c) == False{} : Bool}
  exs p: P.Para
  Pair(D1.In(p, P.Para.split(text)),
    Pair({Nat.is_le(U32.to_nat(D1.para.start(p)), i) == True{} : Bool},
      {Nat.is_lt(i, U32.to_nat(D1.para.end(p))) == True{} : Bool}))

# LAW: the paragraphs are in order and disjoint, the text before, between
# and after them is whitespace, every line of a paragraph (the first and
# last too) holds a non-whitespace code point, and two in a row have a
# blank line between them unless the first was cut; for every text shorter
# than 2^32 code points
law para_tiled:
  for +text: String
  for fits: {U32.to_nat(U32.from_nat(String.length(text)))
    == String.length(text) : Nat}
  tiled(text, 0n, P.Para.split(text))
