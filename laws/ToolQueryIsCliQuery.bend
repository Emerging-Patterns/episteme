# `episteme serve` answers MCP tool calls, and an `ask` call reads its
# arguments as `episteme ask` reads its flags. `Tool.query(vals, since,
# question)` takes the call's `filter` strings (each one a `--filter` value),
# its `since` value and its question. With a question, its filter is
# `Filter.parse(vals)`, refused with `Filter.check`'s refusal exactly when the
# command line's filter would be, and the since value is passed on unread, so
# `Ask` reads it as it reads `--since`. A call without a question is refused
# with `Tool.no_question()`, whatever its filter.
import Base
import ../src/filter.bend as F
import ../src/tool.bend as T

# the query a passed check gives, or the check's refusal
def verdict(
  res: Result<&2, &2, String, Unit>,
  sels: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  question: String
) -> Result<&2, &2, String, T.Query>:
  match res:
    case Fail{why}:
      Fail{why}
    case Done{_u}:
      Done{T.Query{sels, since, question}}

# LAW: a call with a question has the command line's filter, refused exactly
# when the command line's check refuses it, and the since value unread
law query_is_cli:
  for +vals: List<&2, String>
  for since: Maybe<&2, String>
  for question: String
  {T.Tool.query(vals, since, Some{question})
    == verdict(F.Filter.check(F.Filter.parse(vals)), F.Filter.parse(vals),
      since, question)
    : Result<&2, &2, String, T.Query>}

# LAW: a call without a question is refused, whatever its filter
law query_needs_question:
  for +vals: List<&2, String>
  for since: Maybe<&2, String>
  {T.Tool.query(vals, since, None{}) == Fail{T.Tool.no_question()}
    : Result<&2, &2, String, T.Query>}
