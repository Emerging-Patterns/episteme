# proofs of laws/DepthLimitsARankedRun.bend
import Base
import ../src/read.bend as Rd
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value
import ../laws/DepthLimitsARankedRun.bend as Laws

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

def Laws.no_depth_announces_as_before(_names, _question, _who):
  {==}

def Laws.depth_follows_the_shards(names, question, n):
  Equal.cong(List<&2, Value.Json>, Value.Json,
    xs => Json.obj([("question", Json.str(question)), ("shards", Json.arr(xs)), ("depth", Json.num(U32.show(n)))]),
    Rd.Read.notice.names(names), Laws.name_objects(names),
    objects_eq(names))

def Laws.depth_follows_the_authors(names, question, name, who, n):
  %strs_eq(who) : {Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(Rd.Read.notice.names(names))),
      ("authors", Json.arr(Json.str(name) <> Rd.Read.notice.strs(who))),
      ("depth", Json.num(U32.show(n)))])
    == Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(Laws.name_objects(names))),
      ("authors", Json.arr(Json.str(name) <> _)),
      ("depth", Json.num(U32.show(n)))]) : Value.Json}
  %objects_eq(names) : {Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(Rd.Read.notice.names(names))),
      ("authors", Json.arr(Json.str(name) <> Rd.Read.notice.strs(who))),
      ("depth", Json.num(U32.show(n)))])
    == Json.obj([("question", Json.str(question)),
      ("shards", Json.arr(_)),
      ("authors", Json.arr(Json.str(name) <> Rd.Read.notice.strs(who))),
      ("depth", Json.num(U32.show(n)))]) : Value.Json}
  {==}

def Laws.flag_sets_the_depth(_n, _config):
  {==}

def Laws.no_flag_leaves_the_configs(_config):
  {==}

# a value read as a number is a depth as the specification says
law said_eq:
  for got: Maybe<&2, U32>
  for text: String
  {Rd.Read.depth.said(got, text) == Laws.said(got, text) : Result<&2, &2, String, Maybe<&2, U32>>}

def said_eq(got, _text):
  match got:
    case None{}:
      {==}
    case Some{_n}:
      {==}

def Laws.depth_is_a_whole_number(text):
  said_eq(U32.read(text), text)
