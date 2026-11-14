# A question may name authors: `episteme ask --author <names>`, and the
# `author` argument of the server's `ask` tool
# (laws/ToolQueryIsCliQuery.bend). `Filter.who(value)` reads the value: with
# none the question names no author; else it names the value's pieces
# between commas, each with its surrounding whitespace trimmed, the empty
# ones dropped, in order.
#
# `Filter.by(who, xs)` for a question that names at least one author keeps
# exactly the excerpts of `xs`, in order, whose record's author is one of
# `who`, compared whole: no excerpt by another author survives, whatever a
# reader returned. So a question about what one speaker said is answered
# with that speaker's paragraphs or with none. A record's author is what its
# connector wrote: in a Claude transcript the user's own lines are the
# user's (laws/UserLineAuthors.bend).
#
# The run's readers are told the authors in the run notice
# (laws/RunNoticeNamesShards.bend); a question that names none is asked
# exactly as before (laws/NoAuthorChangesNothing.bend).
import Base
import ../src/record.bend as R
import ../src/filter.bend as F
import ../src/excerpt.bend as E

# the author of an excerpt's record
def ex.author(cur: E.Ex) -> String:
  match cur:
    case E.Ex{rec, _paras}:
      match rec:
        case R.Record{_id, _ts, _source, author, _thread, _parent, _rps, _ptr}:
          author

# True when author equals one of who
def one_of(who: List<&2, String>, +author: String) -> Bool:
  match who:
    case Nil{}:
      False{}
    case Con{name, rest}:
      Bool.or(String.eq(author, name), one_of(rest, author))

# the excerpts of xs, in order, whose record's author is one of who
def kept_by(xs: List<&2, E.Ex>, +who: List<&2, String>) -> List<&2, E.Ex>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      List.filter.put(E.Ex, x, kept_by(rest, who), one_of(who, ex.author(x)))

# True when every excerpt of xs is by one of who
def all_by(xs: List<&2, E.Ex>, +who: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{x, rest}:
      Bool.and(one_of(who, ex.author(x)), all_by(rest, who))

# LAW: a question that names authors keeps exactly their excerpts, in order
law author_excerpts:
  for +name: String
  for +who: List<&2, String>
  for xs: List<&2, E.Ex>
  {F.Filter.by(name <> who, xs) == kept_by(xs, name <> who) : List<&2, E.Ex>}

# LAW: no excerpt by another author survives
law author_none_other:
  for +name: String
  for +who: List<&2, String>
  for xs: List<&2, E.Ex>
  {all_by(F.Filter.by(name <> who, xs), name <> who) == True{} : Bool}

# LAW: an example: the value's pieces between commas, trimmed, the empty
# ones dropped
law author_value_example:
  for u: Unit
  {F.Filter.who(Some{" noah, agent ,,"}) == ["noah", "agent"] : List<&2, String>}
