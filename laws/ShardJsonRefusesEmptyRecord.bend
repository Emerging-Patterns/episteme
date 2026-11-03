import Base
import ../src/shard.bend as S

# LAW: an example: an item whose record has no paragraphs reads as no shard
law shard_json_bad_rec:
  for u: Unit
  {S.Shard.of_json("{\"n\":1,\"items\":[{\"rec\":{\"id\":\"m1\",\"ts\":\"2026-10-30T12:00:00.000Z\",\"source\":\"chat:honcho\",\"author\":\"noah\",\"thread\":\"\",\"parent\":\"\",\"paras\":[],\"ptr\":\"\"},\"from\":1,\"upto\":1}],\"sources\":[\"chat:honcho\"],\"chars\":60,\"frozen\":true}")
    == None{} : Maybe<&2, S.Shard>}
