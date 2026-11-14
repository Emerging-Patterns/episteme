# proofs of laws/RunNoticeNamesShards.bend
import Base
import ../src/read.bend as Rd
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value
import ../laws/RunNoticeNamesShards.bend as Laws

# the code's name objects are the specification's
law objects_eq:
  for names: List<&2, Rd.Name>
  {Rd.Read.notice.names(names) == Laws.name_objects(names) : List<&2, Value.Json>}

def objects_eq(names):
  match names:
    case Nil{}:
      {==}
    case Con{nm, rest}:
      match nm:
        case Rd.Name{source, n}:
          Equal.cong(List<&2, Value.Json>, List<&2, Value.Json>,
            ys => Json.obj([("source", Json.str(source)), ("n", Json.num(U32.show(n)))]) <> ys,
            Rd.Read.notice.names(rest), Laws.name_objects(rest),
            objects_eq(rest))

def Laws.notice_names_shards(names, question):
  Equal.cong(List<&2, Value.Json>, Value.Json,
    xs => Json.obj([("question", Json.str(question)), ("shards", Json.arr(xs))]),
    Rd.Read.notice.names(names), Laws.name_objects(names),
    objects_eq(names))

# the code's author strings are the specification's
law strs_eq:
  for who: List<&2, String>
  {Rd.Read.notice.strs(who) == Laws.author_strings(who) : List<&2, Value.Json>}

def strs_eq(who):
  match who:
    case Nil{}:
      {==}
    case Con{name, rest}:
      Equal.cong(List<&2, Value.Json>, List<&2, Value.Json>,
        ys => Json.str(name) <> ys,
        Rd.Read.notice.strs(rest), Laws.author_strings(rest),
        strs_eq(rest))

def Laws.notice_names_authors(names, question, name, who):
  %strs_eq(who) : {Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(Rd.Read.notice.names(names))),
      ("authors", Json.arr(Json.str(name) <> Rd.Read.notice.strs(who)))])
    == Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(Laws.name_objects(names))),
      ("authors", Json.arr(Json.str(name) <> _))]) : Value.Json}
  %objects_eq(names) : {Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(Rd.Read.notice.names(names))),
      ("authors", Json.arr(Json.str(name) <> Rd.Read.notice.strs(who)))])
    == Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(_)),
      ("authors", Json.arr(Json.str(name) <> Rd.Read.notice.strs(who)))]) : Value.Json}
  {==}
