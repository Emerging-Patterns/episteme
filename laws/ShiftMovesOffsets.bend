# `Record.shift(r, k)` keeps every field of `r` and moves each paragraph's
# `start` and `end` on by `k`; a paragraph whose offsets slice `text[k:]` to
# its text, moved by `k`, slices `text` to its text, when its start and end
# plus `k` do not wrap past 2^32.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ./defs/Specification.bend as D1

# a paragraph moved by code points on: its start and end plus by
def moved(pa: P.Para, +by: U32) -> P.Para:
  match pa:
    case P.Para{n, start, end, text}:
      P.Para{n, U32.add(start, by), U32.add(end, by), text}

# paragraphs moved by code points on, in order
def moved.all(ps: List<&2, P.Para>, +by: U32) -> List<&2, P.Para>:
  match ps:
    case Nil{}:
      []
    case Con{head, tail}:
      moved(head, by) <> moved.all(tail, by)

# LAW: Record.shift keeps every field of a record and moves each of its
# paragraphs k code points on
law shift_record:
  for id: String
  for ts: String
  for source: String
  for author: String
  for thread: String
  for parent: String
  for paras: List<&2, P.Para>
  for ptr: String
  for +k: U32
  {R.Record.shift(R.Record{id, ts, source, author, thread, parent, paras, ptr}, k)
    == R.Record{id, ts, source, author, thread, parent, moved.all(paras, k), ptr}
    : R.Record}

# LAW: a paragraph whose offsets slice text[k:] to its text, moved k code
# points on, slices text to its text, when its start and end plus k do not
# wrap past 2^32
law shift_offsets:
  for text: String
  for +k: U32
  for p: P.Para
  for hs: {U32.to_nat(D1.para.start(moved(p, k)))
    == Nat.add(U32.to_nat(k), U32.to_nat(D1.para.start(p))) : Nat}
  for he: {U32.to_nat(D1.para.end(moved(p, k)))
    == Nat.add(U32.to_nat(k), U32.to_nat(D1.para.end(p))) : Nat}
  for h: {D1.slice(String.drop(text, U32.to_nat(k)), U32.to_nat(D1.para.start(p)),
    U32.to_nat(D1.para.end(p))) == D1.para.text(p) : String}
  {D1.slice(text, U32.to_nat(D1.para.start(moved(p, k))),
    U32.to_nat(D1.para.end(moved(p, k)))) == D1.para.text(moved(p, k)) : String}
