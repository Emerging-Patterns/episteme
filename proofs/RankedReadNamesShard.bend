# proofs of laws/RankedReadNamesShard.bend
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value
import ../laws/RankedReadNamesShard.bend as Laws

# a ranked flag that is there, else false, is the specification's
law default_eq:
  for m: Maybe<&2, Bool>
  {Maybe.default(&2, Bool, m, False{}) == Laws.true_if(m) : Bool}

def default_eq(m):
  match m:
    case Some{b}:
      {==}
    case None{}:
      {==}

# a parsed answer says ranked as the specification says it
law of_eq:
  for got: Maybe<&2, Value.Json>
  {Rd.Read.ranked.of(got) == Laws.says_ranked(got) : Bool}

def of_eq(got):
  match got:
    case None{}:
      {==}
    case Some{js}:
      default_eq(Json.as_bool(Json.get(js, "ranked")))

# for either status test, the answer is ranked as the specification says
law if_eq:
  for b: Bool
  for text: String
  {Rd.Read.ranked.if(b, text) == Bool.and(b, Laws.says_ranked(Json.parse(text))) : Bool}

def if_eq(b, text):
  match b:
    case True{}:
      of_eq(Json.parse(text))
    case False{}:
      {==}

def Laws.ranked_is_a_ranked_200(status, text):
  if_eq(U32.is_eq(status, 200), text)

def Laws.ranked_read_names_shard(_slot, _s, nm, _question):
  match nm:
    case Rd.Name{source, n}:
      {==}

def Laws.unranked_read_is_chat(_slot, _s, _nm, _question):
  {==}
