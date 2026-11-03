import Base
import ../src/shard.bend as S

# LAW: an example: items that are no array read as no shard
law shard_json_items_obj:
  for u: Unit
  {S.Shard.of_json("{\"n\":1,\"items\":{},\"sources\":[],\"chars\":0,\"frozen\":false}")
    == None{} : Maybe<&2, S.Shard>}
