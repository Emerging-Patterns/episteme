# For every text shorter than 2^32 code points, `text[start:end] == para.text`
# for every paragraph, and numbering is 1..k with no gaps.
import Base
import ../src/para.bend as P
import ./defs/Specification.bend as D1

# LAW: slicing a text at a paragraph's offsets gives the paragraph's text,
# for every text whose length survives a round trip through U32 (shorter
# than 2^32 code points)
law para_offsets:
  for +text: String
  for fits: {U32.to_nat(U32.from_nat(String.length(text)))
    == String.length(text) : Nat}
  for p: P.Para
  for h: D1.In(p, P.Para.split(text))
  {D1.slice(text, U32.to_nat(D1.para.start(p)), U32.to_nat(D1.para.end(p)))
    == D1.para.text(p) : String}

# LAW: the paragraphs are numbered 1, 2, ... up to how many there are
law para_numbered:
  for +text: String
  {D1.numbers(P.Para.split(text))
    == D1.upto(List.length(&2, P.Para, P.Para.split(text)), 1) : List<&2, U32>}
