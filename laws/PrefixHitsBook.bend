import Base
import ../src/filter.bend as F

# LAW: an example: book:venaya/ hits a shard of book:venaya/b1
law hits_example:
  for u: Unit
  {F.Filter.hits(F.Filter.parse(["book:venaya/"]), ["book:venaya/b1"])
    == True{} : Bool}
