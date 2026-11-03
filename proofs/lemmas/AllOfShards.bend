# All over a list and over the shards a step freezes
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../laws/RecordsSplitOnlyWhenTooBig.bend as L1
import ../../laws/defs/ListMembership.bend as D1
import ../../laws/defs/Specification.bend as D2

# P holds of each of xs
def All(-A: Data, P: A -> Type, xs: List<&2, A>) -> Type:
  match xs:
    case Nil{}:
      Unit
    case Con{head, tail}:
      Pair(P(head), All(A, P, tail))

# All of xs ++ ys from All of each
def all_app(
  -A: Data,
  -P: A -> Type,
  xs: List<&2, A>,
  -ys: List<&2, A>,
  ax: All(A, P, xs),
  ay: All(A, P, ys)
) -> All(A, P, List.append(&2, A, xs, ys)):
  match xs:
    case Nil{}:
      ay
    case Con{_h, t}:
      match ax:
        case (ph, at):
          (ph, all_app(A, P, t, ys, at, ay))

# what All says of one of the list
def all_elem(
  -A: Data,
  -P: A -> Type,
  xs: List<&2, A>,
  -x: A,
  ax: All(A, P, xs),
  hx: D1.Elem(A, x, xs)
) -> P(x):
  match xs:
    case Nil{}:
      Empty.absurd(P(x), hx)
    case Con{h, t}:
      match ax:
        case (ph, at):
          match hx:
            case Inl{e}:
              %Equal.sym(A, x, h, e) : P(_)
              ph
            case Inr{ht}:
              all_elem(A, P, t, x, at, ht)

# the number after es, numbered from n
def after(es: List<&2, S.Open>, +n: U32) -> U32:
  match es:
    case Nil{}:
      n
    case Con{_e, rest}:
      after(rest, U32.inc(n))

# --- which shard is which ---

# s is one of gs, made into a shard
def made_in(gs: List<&2, S.Open>, s: S.Shard) -> Type:
  Exists(S.Open, g => Exists(U32, k => Exists(Bool, f =>
    Pair(D1.Elem(S.Open, g, gs), {s == S.Shard.make(k, g, f) : S.Shard}))))

# made_in rest, so made_in g ahead of it too
def made_up(
  -g: S.Open,
  -rest: List<&2, S.Open>,
  -s: S.Shard,
  x: made_in(rest, s)
) -> made_in(g <> rest, s):
  match x:
    case (g2, (k, (f, (el, e)))):
      (g2, (k, (f, (Inr{el}, e))))

# a shard of number(gs, n) is one of gs, made into a shard
def number_elem(
  gs: List<&2, S.Open>,
  +n: U32,
  -s: S.Shard,
  hs: D1.Elem(S.Shard, s, S.Shard.number(gs, n))
) -> made_in(gs, s):
  match gs:
    case Nil{}:
      Empty.absurd(made_in([], s), hs)
    case Con{+g, +rest}:
      match hs:
        case Inl{e}:
          (g, (n, (S.Shard.more(rest), (Inl{{==}}, e))))
        case Inr{h}:
          made_up(g, rest, s, number_elem(rest, U32.inc(n), s, h))

# --- sizes ---

# the record's own text count is the specification's
law texts_same:
  for ps: List<&2, P.Para>
  {R.Record.texts(ps) == D2.texts(ps) : Nat}

def texts_same(ps):
  match ps:
    case Nil{}:
      {==}
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, +text}:
          Equal.cong(Nat, Nat, x => Nat.add(String.length(text), x),
            R.Record.texts(rest), D2.texts(rest), texts_same(rest))

# Record.size is the specification's size
law size_same:
  for r: R.Record
  {R.Record.size(r) == L1.rsize(r) : Nat}

def size_same(r):
  match r:
    case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
      Equal.cong(Nat, Nat,
        x => Nat.add(String.length(R.Record.header(R.Record{id, ts, source,
          author, thread, parent, paras, ptr})), x),
        R.Record.texts(paras), D2.texts(paras), texts_same(paras))

# --- what holds of every open shard ---

# an open shard's items
def open.items(g: S.Open) -> List<&2, S.Item>:
  match g:
    case S.Open{items, _size}:
      items

# P holds of every shard a step freezes and of the open one after it
def StepAll(P: S.Open -> Type, t: S.Step) -> Type:
  match t:
    case S.Step{out, next}:
      Pair(All(S.Open, P, out), P(next))

# StepAll of a shard frozen ahead of a step
def emit_all(
  -P: S.Open -> Type,
  -o: S.Open,
  t: S.Step,
  ho: P(o),
  ht: StepAll(P, t)
) -> StepAll(P, S.Shard.emit(o, t)):
  match t:
    case S.Step{_out, _next}:
      match ht:
        case (a, b):
          ((ho, a), b)

# StepAll of shards frozen ahead of a step
def after_all(
  -P: S.Open -> Type,
  out: List<&2, S.Open>,
  t: S.Step,
  ho: All(S.Open, P, out),
  ht: StepAll(P, t)
) -> StepAll(P, S.Shard.after(out, t)):
  match t:
    case S.Step{more, _next}:
      match ht:
        case (a, b):
          (all_app(S.Open, P, out, more, ho, a), b)

# All of the open shard frozen, when it holds of the open shard
def shut_all(
  -P: S.Open -> Type,
  cur: List<&2, S.Item>,
  -size: Nat,
  h: P(S.Open{cur, size})
) -> All(S.Open, P, S.Shard.shut(cur, size)):
  match cur:
    case Nil{}:
      Unit{}
    case Con{_head, _tail}:
      (h, Unit{})

# All of a step's shards, then what the rest packs
def then_all(
  -P: S.Open -> Type,
  t: S.Step,
  -rest: List<&2, R.Record>,
  -cap: Nat,
  ht: StepAll(P, t),
  ih: @o: S.Open -> P(o) -> All(S.Open, P, S.Shard.run(rest, cap, o))
) -> All(S.Open, P, S.Shard.then(t, o => S.Shard.run(rest, cap, o))):
  match t:
    case S.Step{out, next}:
      match ht:
        case (a, b):
          all_app(S.Open, P, out, S.Shard.run(rest, cap, next), a, ih(next, b))

# is_ge answers what not is_lt answers, for every order
def ge_not_lt.cmp(c: Cmp) -> {Cmp.is_ge(c) == Bool.not(Cmp.is_lt(c)) : Bool}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      {==}

# a text is at or after another exactly when it is not before it
def ge_not_lt(+a: String, +b: String) -> {String.is_ge(a, b) == D2.at_or_after(a, b) : Bool}:
  ge_not_lt.cmp(String.order(a, b))
