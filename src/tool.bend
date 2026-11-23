# episteme/src/tool: the arguments of an `episteme serve` tool call, read as
# the command line reads its flags (laws/ToolQueryIsCliQuery.bend). Pure: the
# server in main.bend runs what this decides.
#
# Trusted, not proved: `Tool.strings(v)` is `[s]` for a JSON string `s`, the
# string items of a JSON array in order (other items dropped), and `[]` for
# anything else, so a `filter` given as one comma-separated string and one
# given as an array of them read alike. `Tool.text(v)` is a JSON string's
# text or a JSON number as it is written, and nothing for anything else, so
# a `depth` given as "4000" and one given as 4000 read alike.
#
# Why it is trusted: it is ezjson's `as_str`, `as_num` and `items`, whose
# guarantees are ezjson's own; `tests/serve.sh` checks both shapes of each.
import Base
import ./filter.bend as F
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value

# an ask call's question, its filter, its since value, the authors it
# names and its depth value
type Query is Data:
  Query{filter: List<&2, F.Sel>, since: Maybe<&2, String>, who: List<&2, String>, question: String,
    depth: Maybe<&2, String>}

# the refusal of an ask call without a question
def Tool.no_question() -> String:
  "ask needs a question"

# the query when the filter's check passed, else its refusal
def Tool.checked(
  res: Result<&2, &2, String, Unit>,
  sels: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  who: List<&2, String>,
  question: String,
  depth: Maybe<&2, String>
) -> Result<&2, &2, String, Query>:
  match res:
    case Fail{why}:
      Fail{why}
    case Done{_u}:
      Done{Query{sels, since, who, question, depth}}

# an ask call from its filter strings, since value, author value, question
# and depth value: refused without a question, else the command line's
# filter, refused as the command line refuses it, the authors the command
# line reads from the value, and the since and depth values as they came
def Tool.query(
  +refs: List<&2, F.Refusal>,
  +vals: List<&2, String>,
  since: Maybe<&2, String>,
  author: Maybe<&2, String>,
  question: Maybe<&2, String>,
  depth: Maybe<&2, String>
) -> Result<&2, &2, String, Query>:
  match question:
    case None{}:
      Fail{Tool.no_question()}
    case Some{q}:
      Tool.checked(F.Filter.check(refs, F.Filter.parse(vals)), F.Filter.parse(vals), since,
        F.Filter.who(author), q, depth)

# s ahead of more when the item was a string, else more
def Tool.string.or(got: Maybe<&2, String>, more: List<&2, String>) -> List<&2, String>:
  match got:
    case None{}:
      more
    case Some{s}:
      s <> more

# the strings of JSON items, others dropped
def Tool.strings.of(vs: List<&2, Value.Json>) -> List<&2, String>:
  match vs:
    case Nil{}:
      []
    case Con{v, rest}:
      Tool.string.or(Json.as_str(v), Tool.strings.of(rest))

# one string as one value, else the items' strings
def Tool.strings.if(got: Maybe<&2, String>, +val: Value.Json) -> List<&2, String>:
  match got:
    case Some{s}:
      [s]
    case None{}:
      Tool.strings.of(Json.items(val))

# a string as one value, an array as its strings, else none
def Tool.strings(+val: Value.Json) -> List<&2, String>:
  Tool.strings.if(Json.as_str(val), val)

# a string's text, else a number as it is written
def Tool.text.if(got: Maybe<&2, String>, val: Value.Json) -> Maybe<&2, String>:
  match got:
    case Some{s}:
      Some{s}
    case None{}:
      Json.as_num(val)

# a string's text or a number as it is written, else nothing
def Tool.text(+val: Value.Json) -> Maybe<&2, String>:
  Tool.text.if(Json.as_str(val), val)

# an ask call from its arguments object
def Tool.ask(+refs: List<&2, F.Refusal>, +args: Value.Json) -> Result<&2, &2, String, Query>:
  Tool.query(refs, Tool.strings(Json.get(args, "filter")),
    Json.as_str(Json.get(args, "since")), Json.as_str(Json.get(args, "author")),
    Json.as_str(Json.get(args, "question")), Tool.text(Json.get(args, "depth")))
