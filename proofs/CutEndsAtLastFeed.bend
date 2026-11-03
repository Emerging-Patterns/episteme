# proofs of laws/CutEndsAtLastFeed.bend
import Base
import ../src/chat.bend as C
import ../laws/CutEndsAtLastFeed.bend as Laws
import ./lemmas/BoolFacts.bend as M1
import ./lemmas/NatArithmetic.bend as M2

# a read on past bytes the rest of which hold no line feed, b one of them
def cut_none_at(
  f: Bool,
  rest: List<&2, U32>,
  +i: Nat,
  +last: Nat,
  h: {Bool.and(Bool.not(f), Laws.feedless(rest)) == True{} : Bool},
  ih: {Laws.feedless(rest) == True{} : Bool} -> {C.Chat.cut.go(rest, 1n+i, last) == last : Nat}
) -> {C.Chat.cut.go(rest, 1n+i, Bool.pick(Nat, f, 1n+i, last)) == last : Nat}:
  match f:
    case True{}:
      Empty.absurd({C.Chat.cut.go(rest, 1n+i, 1n+i) == last : Nat}, M1.clash(h))
    case False{}:
      ih(h)

# bytes with no line feed leave the answer as it was
def cut_none_go(
  ys: List<&2, U32>,
  +i: Nat,
  +last: Nat,
  h: {Laws.feedless(ys) == True{} : Bool}
) -> {C.Chat.cut.go(ys, i, last) == last : Nat}:
  match ys:
    case Nil{}:
      {==}
    case Con{b, +rest}:
      cut_none_at(U32.is_eq(b, 10), rest, i, last, h,
        h2 => cut_none_go(rest, 1n+i, last, h2))

def Laws.cut_none(ys, h):
  cut_none_go(ys, 0n, 0n, h)

# the cut of xs, a line feed and bytes with none, i bytes before them
def cut_last_go(
  xs: List<&2, U32>,
  +ys: List<&2, U32>,
  +i: Nat,
  last: Nat,
  h: {Laws.feedless(ys) == True{} : Bool}
) -> {C.Chat.cut.go(List.append(&2, U32, xs, 10 <> ys), i, last)
    == Nat.add(i, 1n+List.length(&2, U32, xs)) : Nat}:
  match xs:
    case Nil{}:
      Equal.trans(Nat, C.Chat.cut.go(ys, 1n+i, 1n+i), 1n+i, Nat.add(i, 1n),
        cut_none_go(ys, 1n+i, 1n+i, h),
        Equal.sym(Nat, Nat.add(i, 1n), 1n+i, M2.add_one(i)))
    case Con{x, +xt}:
      Equal.trans(Nat,
        C.Chat.cut.go(List.append(&2, U32, xt, 10 <> ys), 1n+i,
          Bool.pick(Nat, U32.is_eq(x, 10), 1n+i, last)),
        1n+Nat.add(i, 1n+List.length(&2, U32, xt)),
        Nat.add(i, 1n+(1n+List.length(&2, U32, xt))),
        cut_last_go(xt, ys, 1n+i, Bool.pick(Nat, U32.is_eq(x, 10), 1n+i, last), h),
        Equal.sym(Nat, Nat.add(i, 1n+(1n+List.length(&2, U32, xt))),
          1n+Nat.add(i, 1n+List.length(&2, U32, xt)),
          M2.add_succ_r(i, 1n+List.length(&2, U32, xt))))

def Laws.cut_last(xs, ys, h):
  cut_last_go(xs, ys, 0n, 0n, h)

def Laws.from_bytes(_file, _lines, _bytes):
  {==}

def Laws.from_lines(_file, _lines):
  {==}
