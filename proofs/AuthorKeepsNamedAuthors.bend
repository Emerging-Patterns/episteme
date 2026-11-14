# proofs of laws/AuthorKeepsNamedAuthors.bend
import Base
import ../src/record.bend as R
import ../src/filter.bend as F
import ../src/excerpt.bend as E
import ../laws/AuthorKeepsNamedAuthors.bend as Laws
import ./lemmas/TakeAndAppend.bend as M2

# for either answer of the first test, the code's lazy any is the
# specification's or
def any_or(
  b: Bool,
  p: Bool,
  q: Bool,
  e: {p == q : Bool}
) -> {List.any.if(_u => p, b) == Bool.or(b, q) : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      e

# the code's test of an author is the specification's
law named_eq:
  for who: List<&2, String>
  for +author: String
  {F.Filter.named(who, author) == Laws.one_of(who, author) : Bool}

def named_eq(who, author):
  match who:
    case Nil{}:
      {==}
    case Con{name, +rest}:
      any_or(String.eq(author, name), F.Filter.named(rest, author),
        Laws.one_of(rest, author), named_eq(rest, author))

# the code's test of an excerpt's author is the specification's
def named_author(
  +who: List<&2, String>,
  x: E.Ex
) -> {F.Filter.named(who, E.Excerpt.author(E.Excerpt.rec(x)))
    == Laws.one_of(who, Laws.ex.author(x)) : Bool}:
  match x:
    case E.Ex{rec, _ps}:
      match rec:
        case R.Record{_id, _ts, _source, author, _thread, _parent, _paras, _ptr}:
          named_eq(who, author)

# the code keeps the excerpts the specification keeps
law go_eq:
  for xs: List<&2, E.Ex>
  for +who: List<&2, String>
  {F.Filter.by.go(xs, who) == Laws.kept_by(xs, who) : List<&2, E.Ex>}

def go_eq(xs, who):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %named_author(who, x) : {List.filter.put(E.Ex, x, F.Filter.by.go(rest, who),
        F.Filter.named(who, E.Excerpt.author(E.Excerpt.rec(x))))
        == List.filter.put(E.Ex, x, Laws.kept_by(rest, who), _) : List<&2, E.Ex>}
      %go_eq(rest, who) : {List.filter.put(E.Ex, x, F.Filter.by.go(rest, who),
        F.Filter.named(who, E.Excerpt.author(E.Excerpt.rec(x))))
        == List.filter.put(E.Ex, x, _, F.Filter.named(who, E.Excerpt.author(E.Excerpt.rec(x))))
        : List<&2, E.Ex>}
      {==}

def Laws.author_excerpts(name, who, xs):
  go_eq(xs, name <> who)

# an excerpt put ahead of excerpts all by one of who, when the test keeps
# it, leaves all by one of who
def all_put(
  b: Bool,
  +x: E.Ex,
  -r: List<&2, E.Ex>,
  +who: List<&2, String>,
  eb: {Laws.one_of(who, Laws.ex.author(x)) == b : Bool},
  er: {Laws.all_by(r, who) == True{} : Bool}
) -> {Laws.all_by(List.filter.put(E.Ex, x, r, b), who) == True{} : Bool}:
  match b:
    case True{}:
      M2.and_tt(Laws.one_of(who, Laws.ex.author(x)), Laws.all_by(r, who), eb, er)
    case False{}:
      er

# every excerpt the code keeps is by one of who
law go_all:
  for xs: List<&2, E.Ex>
  for +who: List<&2, String>
  {Laws.all_by(F.Filter.by.go(xs, who), who) == True{} : Bool}

def go_all(xs, who):
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      %Equal.sym(Bool, F.Filter.named(who, E.Excerpt.author(E.Excerpt.rec(x))),
          Laws.one_of(who, Laws.ex.author(x)), named_author(who, x))
        : {Laws.all_by(List.filter.put(E.Ex, x, F.Filter.by.go(rest, who), _), who)
          == True{} : Bool}
      all_put(Laws.one_of(who, Laws.ex.author(x)), x, F.Filter.by.go(rest, who), who,
        {==}, go_all(rest, who))

def Laws.author_none_other(name, who, xs):
  go_all(xs, name <> who)

def Laws.author_value_example(_u):
  {==}
