# `episteme serve` answers MCP tool calls, and an `ask` call reads its
# arguments as `episteme ask` reads its flags. `Tool.query(vals, since,
# author, question)` takes the call's `filter` strings (each one a `--filter`
# value), its `since` value, its `author` value and its question. With a
# question, its filter is `Filter.parse(vals)`, refused with `Filter.check`'s
# refusal exactly when the command line's filter would be, the since value is
# passed on unread, so `Ask` reads it as it reads `--since`, and its authors
# are `Filter.who(author)`, the authors `--author` names
# (laws/AuthorKeepsNamedAuthors.bend). A call without a question is refused
# with `Tool.no_question()`, whatever else it holds.
import Base
import ../src/filter.bend as F
import ../src/tool.bend as T

# the query a passed check gives, or the check's refusal
def verdict(
  res: Result<&2, &2, String, Unit>,
  sels: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  who: List<&2, String>,
  question: String
) -> Result<&2, &2, String, T.Query>:
  match res:
    case Fail{why}:
      Fail{why}
    case Done{_u}:
      Done{T.Query{sels, since, who, question}}

# LAW: a call with a question has the command line's filter, refused exactly
# when the command line's check refuses it, the since value unread, and the
# authors the command line reads from the author value
law query_is_cli:
  for +vals: List<&2, String>
  for since: Maybe<&2, String>
  for author: Maybe<&2, String>
  for question: String
  {T.Tool.query(vals, since, author, Some{question})
    == verdict(F.Filter.check(F.Filter.parse(vals)), F.Filter.parse(vals),
      since, F.Filter.who(author), question)
    : Result<&2, &2, String, T.Query>}

# LAW: a call without a question is refused, whatever else it holds
law query_needs_question:
  for +vals: List<&2, String>
  for since: Maybe<&2, String>
  for author: Maybe<&2, String>
  {T.Tool.query(vals, since, author, None{}) == Fail{T.Tool.no_question()}
    : Result<&2, &2, String, T.Query>}
