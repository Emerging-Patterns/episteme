import Base
import ../src/shard.bend as S

# LAW: an example: a name with a bare . is no source's
law undir_dot:
  for u: Unit
  {S.Shard.undir("tail.json") == None{} : Maybe<&2, String>}
