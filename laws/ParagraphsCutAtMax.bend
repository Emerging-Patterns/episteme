# No paragraph text is longer than `Para.max()`; a longer run is cut at the
# last newline at or before the limit, else hard at the limit.
import Base
import ../src/para.bend as P
import ./defs/Specification.bend as D1

# LAW: no paragraph's text is longer than Para.max()
law para_max:
  for +text: String
  for p: P.Para
  for h: D1.In(p, P.Para.split(text))
  {Nat.is_le(String.length(D1.para.text(p)), U32.to_nat(P.Para.max()))
    == True{} : Bool}

# the paragraph ends its run: at the end of the text, or at a line feed
# followed by a blank line
def run_end(text: String, pa: P.Para) -> Type:
  Or({D1.after(text, pa) == "" : String},
    Exists(Char, head => Exists(String, rest =>
      Pair({D1.after(text, pa) == SCon{head, rest} : String},
      Pair({D1.nl(head) == True{} : Bool},
        {D1.blank(D1.line(rest)) == True{} : Bool})))))

# LAW: a paragraph ends where its run ends, or is cut at the last line
# feed at or before Para.max() (the next line would not fit), or else hard
# at Para.max(), for every text shorter than 2^32 code points
law para_cut:
  for +text: String
  for fits: {U32.to_nat(U32.from_nat(String.length(text)))
    == String.length(text) : Nat}
  for p: P.Para
  for h: D1.In(p, P.Para.split(text))
  Or(run_end(text, p), Or(D1.cut_feed(text, p), D1.cut_hard(p)))
