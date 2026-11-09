import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/read.bend as Rd
import ezjson@1.2.0.0/main.bend as Json

# LAW: an example: a shard of three paragraphs admits the ids p1, p2 and
# p3, at most three of them.
law schema_example:
  for u: Unit
  {Json.print(Rd.Read.schema(Rd.Read.paras(S.Shard{1, [S.Item{R.Record{"a", "t", "s", "w", "", "",
      [P.Para{1, 0, 1, "x"}, P.Para{2, 2, 3, "y"}, P.Para{3, 4, 5, "z"}], ""}, 1, 3}],
      ["s"], 0, True{}})))
    == "{\"type\":\"json_schema\",\"json_schema\":{\"schema\":{\"type\":\"object\",\"properties\":{\"ids\":{\"type\":\"array\",\"items\":{\"enum\":[\"p1\",\"p2\",\"p3\"]},\"maxItems\":3}},\"required\":[\"ids\"]}}}"
    : String}
