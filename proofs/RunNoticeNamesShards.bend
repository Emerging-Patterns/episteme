# proofs of laws/RunNoticeNamesShards.bend
import Base
import ../src/read.bend as Rd
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value
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
