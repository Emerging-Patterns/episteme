# which paragraphs a piece cut from a record holds
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../laws/defs/Specification.bend as D1
import ./NatArithmetic.bend as M1
import ./PackingSteps.bend as M2

# --- where an item's paragraphs are ---

# taking j back off j + x leaves x
law sub_add_l:
  for +j: Nat
  for +x: Nat
  {Nat.sub(Nat.add(j, x), j) == x : Nat}

def sub_add_l(j, x):
  match j:
    case 0n:
      M1.sub_zero(x)
    case 1n+p:
      sub_add_l(p, x)

# taking as many as acc has from acc ++ rest gives acc
def take_app_len(
  -A: Data,
  acc: List<&2, A>,
  rest: List<&2, A>
) -> {List.take(&2, A, List.append(&2, A, acc, rest), List.length(&2, A, acc)) == acc : List<&2, A>}:
  match acc:
    case Nil{}:
      match rest:
        case Nil{}:
          {==}
        case Con{_h, _t}:
          {==}
    case Con{+h, t}:
      Equal.cong(List<&2, A>, List<&2, A>, x => h <> x,
        List.take(&2, A, List.append(&2, A, t, rest), List.length(&2, A, t)), t,
        take_app_len(A, t, rest))

# taking as many as xs has gives xs
def take_all(
  -A: Data,
  xs: List<&2, A>
) -> {List.take(&2, A, xs, List.length(&2, A, xs)) == xs : List<&2, A>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, t}:
      Equal.cong(List<&2, A>, List<&2, A>, x => h <> x,
        List.take(&2, A, t, List.length(&2, A, t)), t, take_all(A, t))

# dropping as many as acc has from acc ++ rest leaves rest
def drop_app_len(
  -A: Data,
  acc: List<&2, A>,
  rest: List<&2, A>
) -> {List.drop(&2, A, List.append(&2, A, acc, rest), List.length(&2, A, acc)) == rest : List<&2, A>}:
  match acc:
    case Nil{}:
      M1.drop_zero_l(A, rest)
    case Con{_h, t}:
      drop_app_len(A, t, rest)

# the length of acc ++ b
def llen_app(
  -A: Data,
  acc: List<&2, A>,
  -b: List<&2, A>
) -> {List.length(&2, A, List.append(&2, A, acc, b)) == Nat.add(List.length(&2, A, acc), List.length(&2, A, b)) : Nat}:
  match acc:
    case Nil{}:
      {==}
    case Con{_h, t}:
      Equal.cong(Nat, Nat, x => 1n+x, List.length(&2, A, List.append(&2, A, t, b)),
        Nat.add(List.length(&2, A, t), List.length(&2, A, b)), llen_app(A, t, b))

# the goal of piece_paras, with the start's round trip as a
def pp1(ps: List<&2, P.Para>, acc: List<&2, P.Para>, b: Nat, a: Nat) -> Type:
  {List.take(&2, P.Para, List.drop(&2, P.Para, ps, Nat.sub(a, 1n)), Nat.sub(1n+b, a))
    == acc : List<&2, P.Para>}

# the goal of piece_paras, with the end's round trip as b
def pp2(ps: List<&2, P.Para>, acc: List<&2, P.Para>, +j: Nat, b: Nat) -> Type:
  {List.take(&2, P.Para, List.drop(&2, P.Para, ps, Nat.sub(j, 0n)), Nat.sub(b, j))
    == acc : List<&2, P.Para>}

# the goal of piece_paras, dropping x
def pp3(ps: List<&2, P.Para>, acc: List<&2, P.Para>, +j: Nat, +m: Nat, x: Nat) -> Type:
  {List.take(&2, P.Para, List.drop(&2, P.Para, ps, x), Nat.sub(1n+Nat.add(j, m), j))
    == acc : List<&2, P.Para>}

# the goal of piece_paras, taking from y
def pp4(acc: List<&2, P.Para>, +j: Nat, +m: Nat, y: List<&2, P.Para>) -> Type:
  {List.take(&2, P.Para, y, Nat.sub(1n+Nat.add(j, m), j)) == acc : List<&2, P.Para>}

# the goal of piece_paras, taking z
def pp5(+acc: List<&2, P.Para>, rest: List<&2, P.Para>, z: Nat) -> Type:
  {List.take(&2, P.Para, List.append(&2, P.Para, acc, rest), z) == acc : List<&2, P.Para>}

# the piece from j + 1 to j + 1 + m holds the 1 + m paragraphs after the
# first j, when its end survives the round trip through U32
def piece_paras(
  +rec: R.Record,
  +j: Nat,
  +m: Nat,
  +acc: List<&2, P.Para>,
  +rest: List<&2, P.Para>,
  hd: {List.drop(&2, P.Para, D1.rec.paras(rec), j) == List.append(&2, P.Para, acc, rest) : List<&2, P.Para>},
  hl: {List.length(&2, P.Para, acc) == 1n+m : Nat},
  +hr: {U32.to_nat(U32.from_nat(1n+Nat.add(j, m))) == 1n+Nat.add(j, m) : Nat}
) -> {D1.item.paras(S.Shard.piece(rec, j, m)) == acc : List<&2, P.Para>}:
  %Equal.sym(Nat, U32.to_nat(U32.from_nat(1n+j)), 1n+j, M1.rt_add(1n+j, m, hr))
    : pp1(D1.rec.paras(rec), acc, U32.to_nat(U32.from_nat(1n+Nat.add(j, m))), _)
  %Equal.sym(Nat, U32.to_nat(U32.from_nat(1n+Nat.add(j, m))), 1n+Nat.add(j, m), hr)
    : pp2(D1.rec.paras(rec), acc, j, _)
  %Equal.sym(Nat, Nat.sub(j, 0n), j, M1.sub_zero(j))
    : pp3(D1.rec.paras(rec), acc, j, m, _)
  %Equal.sym(List<&2, P.Para>, List.drop(&2, P.Para, D1.rec.paras(rec), j),
    List.append(&2, P.Para, acc, rest), hd)
    : pp4(acc, j, m, _)
  %Equal.trans(Nat, List.length(&2, P.Para, acc), 1n+m, Nat.sub(1n+Nat.add(j, m), j), hl,
    Equal.sym(Nat, Nat.sub(1n+Nat.add(j, m), j), 1n+m,
      Equal.trans(Nat, Nat.sub(1n+Nat.add(j, m), j), Nat.sub(Nat.add(j, 1n+m), j), 1n+m,
        Equal.cong(Nat, Nat, z => Nat.sub(z, j), 1n+Nat.add(j, m), Nat.add(j, 1n+m),
          Equal.sym(Nat, Nat.add(j, 1n+m), 1n+Nat.add(j, m), M1.add_succ_r(j, m))),
        sub_add_l(j, 1n+m))))
    : pp5(acc, rest, _)
  take_app_len(P.Para, acc, rest)

# the goal of whole_paras, with the end's round trip as b
def wp(+paras: List<&2, P.Para>, b: Nat) -> Type:
  {List.take(&2, P.Para, List.drop(&2, P.Para, paras, 0n), Nat.sub(b, 0n))
    == paras : List<&2, P.Para>}

# a whole record's item holds all its paragraphs, when their count
# survives the round trip through U32
def whole_paras(
  rec: R.Record,
  hr: M1.rt(D1.rec.count(rec))
) -> {D1.item.paras(S.Shard.whole(rec)) == D1.rec.paras(rec) : List<&2, P.Para>}:
  match rec:
    case R.Record{_id, _ts, _source, _author, _thread, _parent, +paras, _ptr}:
      %Equal.sym(Nat, U32.to_nat(U32.from_nat(List.length(&2, P.Para, paras))),
        List.length(&2, P.Para, paras), hr)
        : wp(paras, _)
      %Equal.sym(Nat, Nat.sub(List.length(&2, P.Para, paras), 0n),
        List.length(&2, P.Para, paras), M1.sub_zero(List.length(&2, P.Para, paras)))
        : {List.take(&2, P.Para, List.drop(&2, P.Para, paras, 0n), _) == paras
          : List<&2, P.Para>}
      %Equal.sym(List<&2, P.Para>, List.drop(&2, P.Para, paras, 0n), paras,
        M1.drop_zero_l(P.Para, paras))
        : {List.take(&2, P.Para, _, List.length(&2, P.Para, paras)) == paras
          : List<&2, P.Para>}
      take_all(P.Para, paras)

# --- the piece being cut, one paragraph on ---

# a paragraph joins the piece: what follows the first j is acc ++ [pa] ++ rest
def join_hd(
  -ps: List<&2, P.Para>,
  -j: Nat,
  +acc: List<&2, P.Para>,
  +pa: P.Para,
  +rest: List<&2, P.Para>,
  hd: {List.drop(&2, P.Para, ps, j) == List.append(&2, P.Para, acc, pa <> rest) : List<&2, P.Para>}
) -> {List.drop(&2, P.Para, ps, j) == List.append(&2, P.Para, List.append(&2, P.Para, acc, [pa]), rest) : List<&2,
  P.Para>}:
  Equal.trans(List<&2, P.Para>, List.drop(&2, P.Para, ps, j),
    List.append(&2, P.Para, acc, pa <> rest),
    List.append(&2, P.Para, List.append(&2, P.Para, acc, [pa]), rest), hd,
    Equal.sym(List<&2, P.Para>,
      List.append(&2, P.Para, List.append(&2, P.Para, acc, [pa]), rest),
      List.append(&2, P.Para, acc, pa <> rest), M2.lapp_assoc(P.Para, acc, [pa], rest)))

# a paragraph joins the piece: it holds one more
def join_hl(
  +acc: List<&2, P.Para>,
  -pa: P.Para,
  +m: Nat,
  hl: {List.length(&2, P.Para, acc) == 1n+m : Nat}
) -> {List.length(&2, P.Para, List.append(&2, P.Para, acc, [pa])) == 1n+1n+m : Nat}:
  Equal.trans(Nat, List.length(&2, P.Para, List.append(&2, P.Para, acc, [pa])),
    Nat.add(List.length(&2, P.Para, acc), 1n), 1n+1n+m, llen_app(P.Para, acc, [pa]),
    (%Equal.sym(Nat, List.length(&2, P.Para, acc), 1n+m, hl)
      : {Nat.add(_, 1n) == 1n+1n+m : Nat}
    Equal.cong(Nat, Nat, x => 1n+x, Nat.add(m, 1n), 1n+m, M1.add_one(m))))

# a paragraph joins the piece: the round trip still covers what is left
def join_hr(
  +j: Nat,
  +m: Nat,
  +l: Nat,
  hr: M1.rt(Nat.add(Nat.add(j, 1n+m), 1n+l))
) -> M1.rt(Nat.add(Nat.add(j, 1n+1n+m), l)):
  M1.rt_cast(Nat.add(Nat.add(j, 1n+m), 1n+l), Nat.add(Nat.add(j, 1n+1n+m), l),
    Equal.trans(Nat, Nat.add(Nat.add(j, 1n+m), 1n+l), 1n+Nat.add(Nat.add(j, 1n+m), l),
      Nat.add(Nat.add(j, 1n+1n+m), l), M1.add_succ_r(Nat.add(j, 1n+m), l),
      Equal.sym(Nat, Nat.add(Nat.add(j, 1n+1n+m), l), 1n+Nat.add(Nat.add(j, 1n+m), l),
        Equal.cong(Nat, Nat, z => Nat.add(z, l), Nat.add(j, 1n+1n+m),
          1n+Nat.add(j, 1n+m), M1.add_succ_r(j, 1n+m)))),
    hr)

# a piece fills a shard: what follows it is the next paragraph and the rest
def emit_hd(
  +ps: List<&2, P.Para>,
  +j: Nat,
  +m: Nat,
  +acc: List<&2, P.Para>,
  +pa: P.Para,
  +rest: List<&2, P.Para>,
  hd: {List.drop(&2, P.Para, ps, j) == List.append(&2, P.Para, acc, pa <> rest) : List<&2, P.Para>},
  hl: {List.length(&2, P.Para, acc) == 1n+m : Nat}
) -> {List.drop(&2, P.Para, ps, Nat.add(j, 1n+m)) == pa <> rest : List<&2, P.Para>}:
  Equal.trans(List<&2, P.Para>, List.drop(&2, P.Para, ps, Nat.add(j, 1n+m)),
    List.drop(&2, P.Para, List.drop(&2, P.Para, ps, j), 1n+m), pa <> rest,
    M1.drop_add(P.Para, ps, j, 1n+m),
    (%Equal.sym(List<&2, P.Para>, List.drop(&2, P.Para, ps, j),
      List.append(&2, P.Para, acc, pa <> rest), hd)
      : {List.drop(&2, P.Para, _, 1n+m) == pa <> rest : List<&2, P.Para>}
    %hl : {List.drop(&2, P.Para, List.append(&2, P.Para, acc, pa <> rest), _)
      == pa <> rest : List<&2, P.Para>}
    drop_app_len(P.Para, acc, pa <> rest)))

# a piece fills a shard: the round trip still covers what is left
def emit_hr(
  +j: Nat,
  +m: Nat,
  +l: Nat,
  hr: M1.rt(Nat.add(Nat.add(j, 1n+m), 1n+l))
) -> M1.rt(Nat.add(Nat.add(Nat.add(j, 1n+m), 1n+0n), l)):
  M1.rt_cast(Nat.add(Nat.add(j, 1n+m), 1n+l), Nat.add(Nat.add(Nat.add(j, 1n+m), 1n+0n), l),
    Equal.sym(Nat, Nat.add(Nat.add(Nat.add(j, 1n+m), 1n+0n), l),
      Nat.add(Nat.add(j, 1n+m), 1n+l), M1.add_assoc(Nat.add(j, 1n+m), 1n+0n, l)),
    hr)

# the piece's end survives the round trip
def piece_rt(
  +j: Nat,
  +m: Nat,
  +q: Nat,
  hr: M1.rt(Nat.add(Nat.add(j, 1n+m), q))
) -> M1.rt(1n+Nat.add(j, m)):
  M1.rt_cast(Nat.add(j, 1n+m), 1n+Nat.add(j, m), M1.add_succ_r(j, m),
    M1.rt_add(Nat.add(j, 1n+m), q, hr))

# a round trip through U32, as data a proof may use twice
def rtd(+num: Nat) -> Data:
  {U32.to_nat(U32.from_nat(num)) == num : Nat}
