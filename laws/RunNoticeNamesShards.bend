# `Read.notice(names, q, who)` of a question that names no author is exactly
# `{"question": q, "shards": [{"source": s1, "n": n1}, ...]}`, one object per
# name of `names` in order, each shard's own name `Read.Name{source, n}`. Of
# a question that names authors (laws/AuthorKeepsNamedAuthors.bend) it is
# that body with one more field after them, `"authors": [a1, ...]`, the
# authors in order.
#
# Before a run's reads, `ask` POSTs this body to `<url>/v1/episteme/run` on
# every instance of the pool, so a reader that ranks across shards (deploy/f2)
# knows the run's whole
# shard set and fills one budget for it, rather than one per source, and
# from the named authors' paragraphs alone when the question names any. The
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

# authors as JSON strings, in order
def author_strings(who: List<&2, String>) -> List<&2, Value.Json>:
  match who:
    case Nil{}:
      []
    case Con{name, rest}:
      Json.str(name) <> author_strings(rest)

# the notice of a run's shards for a question that names authors
def authored_body(names: List<&2, Rd.Name>, question: String, who: List<&2, String>) -> Value.Json:
  Json.obj([("question", Json.str(question)), ("shards", Json.arr(name_objects(names))),
    ("authors", Json.arr(author_strings(who)))])

# LAW: a run whose question names no author is announced with exactly this
# body
law notice_names_shards:
  for names: List<&2, Rd.Name>
  for question: String
  {Rd.Read.notice(names, question, []) == notice_body(names, question) : Value.Json}

# LAW: a run whose question names authors is announced with the same body
# and the authors after it
law notice_names_authors:
  for names: List<&2, Rd.Name>
  for question: String
  for name: String
  for who: List<&2, String>
  {Rd.Read.notice(names, question, name <> who) == authored_body(names, question, name <> who)
    : Value.Json}
