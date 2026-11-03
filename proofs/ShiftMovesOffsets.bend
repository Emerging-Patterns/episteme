# proofs of laws/ShiftMovesOffsets.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../laws/ShiftMovesOffsets.bend as Laws
import ../laws/defs/Specification.bend as D1

# Record.shift.paras moves each paragraph as the specification says
def shift_moved(
  ps: List<&2, P.Para>,
  +k: U32
) -> {R.Record.shift.paras(ps, k) == Laws.moved.all(ps, k) : List<&2, P.Para>}:
  match ps:
    case Nil{}:
      {==}
    case Con{p, rest}:
      match p:
        case P.Para{+n, +s, +e, +t}:
          Equal.cong(List<&2, P.Para>, List<&2, P.Para>,
            x => P.Para{n, U32.add(s, k), U32.add(e, k), t} <> x,
            R.Record.shift.paras(rest, k), Laws.moved.all(rest, k),
            shift_moved(rest, k))

def Laws.shift_record(id, ts, source, author, thread, parent, paras, ptr, k):
  Equal.cong(List<&2, P.Para>, R.Record,
    x => R.Record{id, ts, source, author, thread, parent, x, ptr},
    R.Record.shift.paras(paras, k), Laws.moved.all(paras, k),
    shift_moved(paras, k))

# dropping a + b code points is dropping a, then b
def sdrop_add(
  s: String,
  a: Nat,
  +b: Nat
) -> {String.drop(s, Nat.add(a, b)) == String.drop(String.drop(s, a), b) : String}:
  match s a:
    case SNil{} _:
      {==}
    case SCon{_h, _t} 0n:
      {==}
    case SCon{_h, t} 1n+p:
      sdrop_add(t, p, b)

# k + e less k + s is e less s
def sub_cancel(
  k: Nat,
  +e: Nat,
  +s: Nat
) -> {Nat.sub(Nat.add(k, e), Nat.add(k, s)) == Nat.sub(e, s) : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      sub_cancel(p, e, s)

# a slice of text[k:] from s to e is the slice of text from k + s to k + e
def shift_slice(
  +text: String,
  +k: Nat,
  +s: Nat,
  +e: Nat,
  -t: String,
  h: {D1.slice(String.drop(text, k), s, e) == t : String}
) -> {D1.slice(text, Nat.add(k, s), Nat.add(k, e)) == t : String}:
  %Equal.sym(String, String.drop(text, Nat.add(k, s)),
    String.drop(String.drop(text, k), s), sdrop_add(text, k, s))
    : {String.take(_, Nat.sub(Nat.add(k, e), Nat.add(k, s))) == t : String}
  %Equal.sym(Nat, Nat.sub(Nat.add(k, e), Nat.add(k, s)), Nat.sub(e, s),
    sub_cancel(k, e, s))
    : {String.take(String.drop(String.drop(text, k), s), _) == t : String}
  h

def Laws.shift_offsets(text, k, p, hs, he, h):
  match p:
    case P.Para{_n, +s, +e, t}:
      %Equal.sym(Nat, U32.to_nat(U32.add(s, k)),
        Nat.add(U32.to_nat(k), U32.to_nat(s)), hs)
        : {D1.slice(text, _, U32.to_nat(U32.add(e, k))) == t : String}
      %Equal.sym(Nat, U32.to_nat(U32.add(e, k)),
        Nat.add(U32.to_nat(k), U32.to_nat(e)), he)
        : {D1.slice(text, Nat.add(U32.to_nat(k), U32.to_nat(s)), _) == t
          : String}
      shift_slice(text, U32.to_nat(k), U32.to_nat(s), U32.to_nat(e), t, h)
