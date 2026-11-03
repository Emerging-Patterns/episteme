import Base
import ../src/shard.bend as S
import ./defs/FrozenShards.bend as D1

# LAW: an example: a shard reads back from its JSON.
law shard_json_example:
  for u: Unit
  {S.Shard.of_json(S.Shard.to_json(D1.json_shard()))
    == Some{D1.json_shard()} : Maybe<&2, S.Shard>}
