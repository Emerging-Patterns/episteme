# proofs of laws/ShardSourcesSorted.bend
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ../laws/ShardSourcesSorted.bend as Laws
import ../laws/defs/Specification.bend as D1
import ./lemmas/AllOfShards.bend as M1
import ./lemmas/BoolFacts.bend as M2
import ./lemmas/TakeAndAppend.bend as M3
import ./lemmas/TextOrder.bend as M4

# a text above another has the other below it
def gt_lt(
  +a: String,
  +y: String,
  e: {String.order(a, y) == GT{} : Cmp}
) -> {String.is_lt(y, a) == True{} : Bool}:
  %Equal.sym(Cmp, String.order.go(y, a, EQ{}),
    M4.cflip(String.order.go(a, y, EQ{})), M4.order_flip(a, y, EQ{}))
    : {Cmp.is_lt(_) == True{} : Bool}
  %Equal.sym(Cmp, String.order(a, y), GT{}, e)
    : {Cmp.is_lt(M4.cflip(_)) == True{} : Bool}
  {==}

# a text is one of the sources of items exactly when it is an item's source
law mem_sources:
  for its: List<&2, S.Item>
  for +x: String
  {D1.mem(x, S.Shard.sources(its)) == D1.has(x, its) : Bool}

def mem_sources(its, x):
  match its:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case S.Item{rec, from, upto}:
          match rec:
            case R.Record{id, ts, +source, author, thread, parent, paras, ptr}:
              Equal.trans(Bool,
                D1.mem(x, S.Shard.insert(S.Shard.sources(rest), source)),
                Bool.or(String.eq(x, source), D1.mem(x, S.Shard.sources(rest))),
                Bool.or(String.eq(x, source), D1.has(x, rest)),
                M4.mem_insert(S.Shard.sources(rest), x, source),
                Equal.cong(Bool, Bool, b => Bool.or(String.eq(x, source), b),
                  D1.mem(x, S.Shard.sources(rest)), D1.has(x, rest),
                  mem_sources(rest, x)))

# a put above prev, at y, by how it compared to y
def asc_from.at(
  c: Cmp,
  +prev: String,
  +a: String,
  +y: String,
  +rest: List<&2, String>,
  +ins: List<&2, String>,
  e: {String.order(a, y) == c : Cmp},
  e1: {String.is_lt(prev, a) == True{} : Bool},
  p1: {String.is_lt(prev, y) == True{} : Bool},
  p2: {D1.ascending.from(rest, y) == True{} : Bool},
  ih: {String.is_lt(y, a) == True{} : Bool} -> {D1.ascending.from(ins, y) == True{} : Bool}
) -> {D1.ascending.from(S.Shard.insert.at(c, a, y, rest, ins), prev) == True{} : Bool}:
  match c:
    case LT{}:
      M3.and_tt(String.is_lt(prev, a),
        Bool.and(String.is_lt(a, y), D1.ascending.from(rest, y)), e1,
        M3.and_tt(String.is_lt(a, y), D1.ascending.from(rest, y),
          Equal.cong(Cmp, Bool, d => Cmp.is_lt(d), String.order(a, y), LT{}, e),
          p2))
    case EQ{}:
      M3.and_tt(String.is_lt(prev, y), D1.ascending.from(rest, y), p1, p2)
    case GT{}:
      M3.and_tt(String.is_lt(prev, y), D1.ascending.from(ins, y), p1,
        ih(gt_lt(a, y, e)))

# a put above prev keeps the texts after prev ascending
law asc_from_insert:
  for +ys: List<&2, String>
  for +prev: String
  for +a: String
  for e1: {String.is_lt(prev, a) == True{} : Bool}
  for +e2: {D1.ascending.from(ys, prev) == True{} : Bool}
  {D1.ascending.from(S.Shard.insert(ys, a), prev) == True{} : Bool}

def asc_from_insert(ys, prev, a, e1, e2):
  match ys:
    case Nil{}:
      M3.and_tt(String.is_lt(prev, a), True{}, e1, {==})
    case Con{+y, +rest}:
      asc_from.at(String.order(a, y), prev, a, y, rest, S.Shard.insert(rest, a),
        {==}, e1, M2.and_l(String.is_lt(prev, y), D1.ascending.from(rest, y), e2),
        M2.and_r(String.is_lt(prev, y), D1.ascending.from(rest, y), e2),
        h => asc_from_insert(rest, y, a, h,
          M2.and_r(String.is_lt(prev, y), D1.ascending.from(rest, y), e2)))

# a put keeps ascending texts ascending, at y by how it compared to y
def asc_insert.at(
  c: Cmp,
  +a: String,
  +y: String,
  +rest: List<&2, String>,
  e: {String.order(a, y) == c : Cmp},
  p: {D1.ascending.from(rest, y) == True{} : Bool}
) -> {D1.ascending(S.Shard.insert.at(c, a, y, rest, S.Shard.insert(rest, a)))
  == True{} : Bool}:
  match c:
    case LT{}:
      M3.and_tt(String.is_lt(a, y), D1.ascending.from(rest, y),
        Equal.cong(Cmp, Bool, d => Cmp.is_lt(d), String.order(a, y), LT{}, e), p)
    case EQ{}:
      p
    case GT{}:
      asc_from_insert(rest, y, a, gt_lt(a, y, e), p)

# a put keeps ascending texts ascending
law asc_insert:
  for +ys: List<&2, String>
  for +a: String
  for e: {D1.ascending(ys) == True{} : Bool}
  {D1.ascending(S.Shard.insert(ys, a)) == True{} : Bool}

def asc_insert(ys, a, e):
  match ys:
    case Nil{}:
      {==}
    case Con{+y, +rest}:
      asc_insert.at(String.order(a, y), a, y, rest, {==}, e)

# the sources of items are ascending
law asc_sources:
  for its: List<&2, S.Item>
  {D1.ascending(S.Shard.sources(its)) == True{} : Bool}

def asc_sources(its):
  match its:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      asc_insert(S.Shard.sources(rest), S.Shard.source(it), asc_sources(rest))

# the claim of laws/ShardSourcesSorted.bend about one shard
def sources_ok(+s: S.Shard, +x: String) -> Type:
  Pair({D1.ascending(Laws.shard.sources(s)) == True{} : Bool},
    {D1.mem(x, Laws.shard.sources(s)) == D1.has(x, D1.shard.items(s)) : Bool})

# laws/ShardSourcesSorted.bend of a made shard
def sources_made(
  +k: U32,
  g: S.Open,
  +f: Bool,
  +x: String
) -> sources_ok(S.Shard.make(k, g, f), x):
  match g:
    case S.Open{+items, size}:
      (asc_sources(items), mem_sources(items, x))

# laws/ShardSourcesSorted.bend of a shard made of one of gs
def sources_in(
  -gs: List<&2, S.Open>,
  -s: S.Shard,
  +x: String,
  m: M1.made_in(gs, s)
) -> sources_ok(s, x):
  match m:
    case (g, (k, (f, (_el, e)))):
      %Equal.sym(S.Shard, s, S.Shard.make(k, g, f), e) : sources_ok(_, x)
      sources_made(k, g, f, x)

# laws/ShardSourcesSorted.bend: a shard's sources are its items' sources, ascending
def Laws.shard_sources(cap, n, xs, s, hs, x):
  sources_in(S.Shard.run(xs, U32.to_nat(cap), S.Open{[], 0n}), s, x,
    M1.number_elem(S.Shard.run(xs, U32.to_nat(cap), S.Open{[], 0n}), n, s, hs))
