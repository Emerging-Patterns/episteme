# A reader that ranked the whole run from its notice is asked for each of
# the run's shards by the shard's own name, and is never sent its text.
#
# `Read.ranked(status, text)` reads the answer to the run notice
# (laws/RunNoticeNamesShards.bend): True exactly when the status is 200 and
# the body is JSON whose `ranked` is `true`. Anything else is False: a 404
# from a reader without the endpoint, a body that is not JSON, a `ranked`
# that is missing or not `true`; src/reader.bend reads a transport error as
# False too. `Read.call(ranked, slot, s, nm, q)` is the call a read of the
# run's shard s, whose own name is nm, makes on an instance's slot:
#
# - when the instance ranked the run, exactly `Read.Call{"/v1/episteme/read",
#   {"question": q, "source": <nm's source>, "n": <nm's n>}}`: the name the
#   notice gave the shard, so the shard is neither rendered nor sent;
# - else exactly `Read.Call{"/v1/chat/completions", Read.request(slot, s, q)}`,
#   the request of laws/RequestAdmitsOnlyLabels.bend, so a reader that did
#   not rank (llama-server) is asked exactly as before.
#
# Either reply is read by `Read.reply` and its labels resolved against the
# shard s (laws/ResolveKeepsNamedParagraphs.bend), so every label still names
# a paragraph of the shard it was read for, and a named read the reader
# cannot answer is a failed read like any other.
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# a boolean that is there, else false
def true_if(got: Maybe<&2, Bool>) -> Bool:
  match got:
    case Some{b}:
      b
    case None{}:
      False{}

# whether a parsed notice answer says ranked: JSON whose ranked is true
def says_ranked(got: Maybe<&2, Value.Json>) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{js}:
      true_if(Json.as_bool(Json.get(js, "ranked")))

# whether a notice answer with this status and body says the run was ranked
def ranked_answer(+status: U32, text: String) -> Bool:
  Bool.and(U32.is_eq(status, 200), says_ranked(Json.parse(text)))

# the body of a named read: the question and the shard's own name
def named_body(nm: Rd.Name, question: String) -> Value.Json:
  match nm:
    case Rd.Name{source, n}:
      Json.obj([("question", Json.str(question)), ("source", Json.str(source)),
        ("n", Json.num(U32.show(n)))])

# LAW: a notice answer means ranked exactly when it is a 200 whose JSON
# ranked is true
law ranked_is_a_ranked_200:
  for status: U32
  for text: String
  {Rd.Read.ranked(status, text) == ranked_answer(status, text) : Bool}

# LAW: a ranked instance is asked for a shard by its own name, with no text
law ranked_read_names_shard:
  for slot: U32
  for s: S.Shard
  for nm: Rd.Name
  for question: String
  {Rd.Read.call(True{}, slot, s, nm, question)
    == Rd.Call{"/v1/episteme/read", named_body(nm, question)} : Rd.Call}

# LAW: any other instance is asked exactly as before
law unranked_read_is_chat:
  for slot: U32
  for s: S.Shard
  for nm: Rd.Name
  for question: String
  {Rd.Read.call(False{}, slot, s, nm, question)
    == Rd.Call{"/v1/chat/completions", Rd.Read.request(slot, s, question)} : Rd.Call}
