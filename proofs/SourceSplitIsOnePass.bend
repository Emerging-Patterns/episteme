# proofs of laws/SourceSplitIsOnePass.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/SourceSplitIsOnePass.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ../laws/defs/Specification.bend as D2
import ./lemmas/PackingSteps.bend as M1
import ./lemmas/TextOrder.bend as M2

# an append after the record kept or not
law src_app_if:
  for b: Bool
  for +r: R.Record
  for a: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  {List.append(&2, R.Record, S.Shard.only.if(b, r, a), ys)
    == S.Shard.only.if(b, r, List.append(&2, R.Record, a, ys)) : List<&2, R.Record>}

def src_app_if(b, _r, _a, _ys):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# Shard.only splits over an append
law src_app:
  for +src: String
  for xs: List<&2, R.Record>
  for +ys: List<&2, R.Record>
  {S.Shard.only(src, List.append(&2, R.Record, xs, ys))
    == List.append(&2, R.Record, S.Shard.only(src, xs), S.Shard.only(src, ys))
    : List<&2, R.Record>}

def src_app(src, xs, ys):
  match xs:
    case Nil{}:
      {==}
    case Con{+rec, +rest}:
      Equal.trans(List<&2, R.Record>,
        S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec,
          S.Shard.only(src, List.append(&2, R.Record, rest, ys))),
        S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec,
          List.append(&2, R.Record, S.Shard.only(src, rest), S.Shard.only(src, ys))),
        List.append(&2, R.Record,
          S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec, S.Shard.only(src, rest)),
          S.Shard.only(src, ys)),
        Equal.cong(List<&2, R.Record>, List<&2, R.Record>,
          l => S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec, l),
          S.Shard.only(src, List.append(&2, R.Record, rest, ys)),
          List.append(&2, R.Record, S.Shard.only(src, rest), S.Shard.only(src, ys)),
          src_app(src, rest, ys)),
        Equal.sym(List<&2, R.Record>,
          List.append(&2, R.Record,
            S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec, S.Shard.only(src, rest)),
            S.Shard.only(src, ys)),
          S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec,
            List.append(&2, R.Record, S.Shard.only(src, rest), S.Shard.only(src, ys))),
          src_app_if(String.eq(S.Shard.src(rec), src), rec, S.Shard.only(src, rest),
            S.Shard.only(src, ys))))

def Laws.only_append(src, xs, ys):
  src_app(src, xs, ys)

# an or whose right side is true is true
def or_true_r(a: Bool, -b: Bool, e: {b == True{} : Bool}) -> {Bool.or(a, b) == True{} : Bool}:
  match a:
    case False{}:
      e
    case True{}:
      {==}

# every record's source is one of Shard.keys
def keys_cover(
  xs: List<&2, R.Record>,
  +r: R.Record,
  h: D1.Elem(R.Record, r, xs)
) -> {D2.mem(D2.rec.source(r), S.Shard.keys(xs)) == True{} : Bool}:
  match xs:
    case Nil{}:
      Empty.absurd({D2.mem(D2.rec.source(r), []) == True{} : Bool}, h)
    case Con{rec, +rest}:
      match rec:
        case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
          match h:
            case Inl{e}:
              %Equal.sym(R.Record, r, R.Record{id, ts, source, author, thread, parent, paras, ptr}, e)
                : {D2.mem(D2.rec.source(_), S.Shard.insert(S.Shard.keys(rest), source))
                  == True{} : Bool}
              Equal.trans(Bool,
                D2.mem(source, S.Shard.insert(S.Shard.keys(rest), source)),
                Bool.or(String.eq(source, source), D2.mem(source, S.Shard.keys(rest))),
                True{},
                M2.mem_insert(S.Shard.keys(rest), source, source),
                (%Equal.sym(Bool, String.eq(source, source), True{}, M1.eq_refl(source))
                  : {Bool.or(_, D2.mem(source, S.Shard.keys(rest))) == True{} : Bool};
                  {==}))
            case Inr{h2}:
              Equal.trans(Bool,
                D2.mem(D2.rec.source(r), S.Shard.insert(S.Shard.keys(rest), source)),
                Bool.or(String.eq(D2.rec.source(r), source),
                  D2.mem(D2.rec.source(r), S.Shard.keys(rest))),
                True{},
                M2.mem_insert(S.Shard.keys(rest), D2.rec.source(r), source),
                or_true_r(String.eq(D2.rec.source(r), source),
                  D2.mem(D2.rec.source(r), S.Shard.keys(rest)),
                  keys_cover(rest, r, h2)))

def Laws.keys_cover(xs, r, h):
  keys_cover(xs, r, h)

# a one-record part kept or not is the record kept or not
def pif_one(
  b: Bool,
  -rec: R.Record,
  -rest: List<&2, R.Record>
) -> {S.Shard.part.if(b, [rec], rest) == S.Shard.only.if(b, rec, rest) : List<&2, R.Record>}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# a part with rec at its front, kept or not
def pif_front(
  b: Bool,
  -rec: R.Record,
  -grs: List<&2, R.Record>,
  -rest: List<&2, R.Record>
) -> {S.Shard.part.if(b, rec <> grs, rest)
    == S.Shard.only.if(b, rec, S.Shard.part.if(b, grs, rest)) : List<&2, R.Record>}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# a text below another is not equal to it
def gt_ne(
  +a: String,
  +y: String,
  e: {String.order(a, y) == GT{} : Cmp}
) -> {String.eq(y, a) == False{} : Bool}:
  %Equal.sym(Cmp, String.order.go(y, a, EQ{}),
    M2.cflip(String.order.go(a, y, EQ{})), M2.order_flip(a, y, EQ{}))
    : {Cmp.is_eq(_) == False{} : Bool}
  %Equal.sym(Cmp, String.order(a, y), GT{}, e)
    : {Cmp.is_eq(M2.cflip(_)) == False{} : Bool}
  {==}

# past a part of a source below rec's, by whether rec is of src
def put_gt.at(
  b: Bool,
  +src: String,
  +t: String,
  +g: String,
  -rec: R.Record,
  +grs: List<&2, R.Record>,
  -rest: List<&2, R.Record>,
  eb: {String.eq(t, src) == b : Bool},
  e: {String.order(t, g) == GT{} : Cmp}
) -> {S.Shard.part.if(String.eq(g, src), grs, S.Shard.only.if(b, rec, rest))
  == S.Shard.only.if(b, rec, S.Shard.part.if(String.eq(g, src), grs, rest)) : List<&2, R.Record>}:
  match b:
    case False{}:
      {==}
    case True{}:
      %M2.order_eq(t, src, EQ{}, eb)
        : {S.Shard.part.if(String.eq(g, _), grs, rec <> rest)
          == rec <> S.Shard.part.if(String.eq(g, _), grs, rest) : List<&2, R.Record>}
      %Equal.sym(Bool, String.eq(g, t), False{}, gt_ne(t, g, e))
        : {S.Shard.part.if(_, grs, rec <> rest)
          == rec <> S.Shard.part.if(_, grs, rest) : List<&2, R.Record>}
      {==}

# rec put into the parts ps is at the front of its source's records
def put_ok(+src: String, +ps: List<&2, S.Part>, +t: String, +rec: R.Record) -> Type:
  {S.Shard.part(src, S.Shard.put(ps, t, rec))
    == S.Shard.only.if(String.eq(t, src), rec, S.Shard.part(src, ps)) : List<&2, R.Record>}

# rec put into parts whose first is g's, by how t compared to g
def put_part.at(
  c: Cmp,
  +src: String,
  +t: String,
  +g: String,
  +rec: R.Record,
  +grs: List<&2, R.Record>,
  +rest: List<&2, S.Part>,
  e: {String.order(t, g) == c : Cmp},
  ih: put_ok(src, rest, t, rec)
) -> {S.Shard.part(src, S.Shard.put.at(c, rec, t, g, grs, rest, _u => S.Shard.put(rest, t, rec)))
  == S.Shard.only.if(String.eq(t, src), rec, S.Shard.part(src, S.Part{g, grs} <> rest))
  : List<&2, R.Record>}:
  match c:
    case LT{}:
      pif_one(String.eq(t, src), rec, S.Shard.part(src, S.Part{g, grs} <> rest))
    case EQ{}:
      %Equal.sym(String, t, g, M2.str_eq(t, g, e))
        : {S.Shard.part.if(String.eq(g, src), rec <> grs, S.Shard.part(src, rest))
          == S.Shard.only.if(String.eq(_, src), rec,
            S.Shard.part.if(String.eq(g, src), grs, S.Shard.part(src, rest)))
          : List<&2, R.Record>}
      pif_front(String.eq(g, src), rec, grs, S.Shard.part(src, rest))
    case GT{}:
      %Equal.sym(List<&2, R.Record>, S.Shard.part(src, S.Shard.put(rest, t, rec)),
        S.Shard.only.if(String.eq(t, src), rec, S.Shard.part(src, rest)), ih)
        : {S.Shard.part.if(String.eq(g, src), grs, _)
          == S.Shard.only.if(String.eq(t, src), rec,
            S.Shard.part.if(String.eq(g, src), grs, S.Shard.part(src, rest)))
          : List<&2, R.Record>}
      put_gt.at(String.eq(t, src), src, t, g, rec, grs, S.Shard.part(src, rest), {==}, e)

# a record put into the parts is at the front of its source's records
law put_part:
  for +src: String
  for +ps: List<&2, S.Part>
  for +t: String
  for +rec: R.Record
  {S.Shard.part(src, S.Shard.put(ps, t, rec))
    == S.Shard.only.if(String.eq(t, src), rec, S.Shard.part(src, ps)) : List<&2, R.Record>}

def put_part(src, ps, t, rec):
  match ps:
    case Nil{}:
      pif_one(String.eq(t, src), rec, [])
    case Con{p, +rest}:
      match p:
        case S.Part{+g, +grs}:
          put_part.at(String.order(t, g), src, t, g, rec, grs, rest, {==},
            put_part(src, rest, t, rec))

# laws/SourceSplitIsOnePass.bend: the one-pass split holds what Shard.only keeps
def Laws.parts_only(src, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+rec, +rest}:
      Equal.trans(List<&2, R.Record>,
        S.Shard.part(src, S.Shard.put(S.Shard.parts(rest), S.Shard.src(rec), rec)),
        S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec, S.Shard.part(src, S.Shard.parts(rest))),
        S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec, S.Shard.only(src, rest)),
        put_part(src, S.Shard.parts(rest), S.Shard.src(rec), rec),
        Equal.cong(List<&2, R.Record>, List<&2, R.Record>,
          l => S.Shard.only.if(String.eq(S.Shard.src(rec), src), rec, l),
          S.Shard.part(src, S.Shard.parts(rest)), S.Shard.only(src, rest),
          Laws.parts_only(src, rest)))
