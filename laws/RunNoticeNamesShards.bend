# `Read.notice(names, q)` is exactly `{"question": q, "shards": [{"source":
# s1, "n": n1}, ...]}`, one object per name of `names` in order, each
# shard's own name `Read.Name{source, n}`.
#
# Before a run's reads, `ask` POSTs this body to `<url>/v1/episteme/run` on
# every instance of the pool, so a reader that ranks across shards (deploy/f2)
# knows the run's whole
# shard set and fills one budget for it, rather than one per source. The
# answer says only whether the reader ranked the run: one that did is then
# asked for each shard by name (laws/RankedReadNamesShard.bend), and a reader
# without that endpoint (llama-server answers 404) reads the run exactly as
# before. Every label still comes from a read of its own shard
# (laws/RequestAdmitsOnlyLabels.bend).
import Base
import ../src/read.bend as Rd
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# a shard's name as an object
def name_object(nm: Rd.Name) -> Value.Json:
  match nm:
    case Rd.Name{source, n}:
      Json.obj([("source", Json.str(source)), ("n", Json.num(U32.show(n)))])

# the names as objects, in order
def name_objects(names: List<&2, Rd.Name>) -> List<&2, Value.Json>:
  match names:
    case Nil{}:
      []
    case Con{nm, rest}:
      name_object(nm) <> name_objects(rest)

# the notice of a run's shards for a question
def notice_body(names: List<&2, Rd.Name>, question: String) -> Value.Json:
  Json.obj([("question", Json.str(question)), ("shards", Json.arr(name_objects(names)))])

# LAW: a run is announced with exactly this body
law notice_names_shards:
  for names: List<&2, Rd.Name>
  for question: String
  {Rd.Read.notice(names, question) == notice_body(names, question) : Value.Json}
