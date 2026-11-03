import Base
import ../src/filter.bend as F

# LAW: an example: book:venaya/ misses a shard of book:venayaX
law misses_example:
  for u: Unit
  {F.Filter.hits(F.Filter.parse(["book:venaya/"]), ["book:venayaX"])
    == False{} : Bool}
