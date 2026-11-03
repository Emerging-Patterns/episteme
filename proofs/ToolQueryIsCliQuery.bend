# proofs of laws/ToolQueryIsCliQuery.bend
import Base
import ../src/filter.bend as F
import ../src/tool.bend as T
import ../laws/ToolQueryIsCliQuery.bend as Laws

# the code's answer for a check is the law's
law checked_eq:
  for res: Result<&2, &2, String, Unit>
  for sels: List<&2, F.Sel>
  for since: Maybe<&2, String>
  for question: String
  {T.Tool.checked(res, sels, since, question)
    == Laws.verdict(res, sels, since, question)
    : Result<&2, &2, String, T.Query>}

def checked_eq(res, _sels, _since, _question):
  match res:
    case Fail{_why}:
      {==}
    case Done{_u}:
      {==}

def Laws.query_is_cli(vals, since, question):
  checked_eq(F.Filter.check(F.Filter.parse(vals)), F.Filter.parse(vals), since, question)

def Laws.query_needs_question(_vals, _since):
  {==}
