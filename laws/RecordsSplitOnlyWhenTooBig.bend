# A record is split across shards only if `Record.chars` exceeds `cap`, and
# only at paragraph boundaries.
import Base
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2

# a record's size: its header line and its paragraph texts
def rsize(+record: R.Record) -> Nat:
  Nat.add(D2.rec.head(record), D2.texts(D2.rec.paras(record)))

# where an item starts in its record
def item.from(it: S.Item) -> U32:
  match it:
    case S.Item{_rec, from, _upto}:
      from

# where an item ends in its record, inclusive
def item.upto(it: S.Item) -> U32:
  match it:
    case S.Item{_rec, _from, upto}:
      upto

# LAW: an item of a record that fits in cap is the whole record: a record
# is split, at paragraph boundaries, only when it does not fit
law shard_whole:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  for s: S.Shard
  for hs: D1.Elem(S.Shard, s, S.Shard.pack(cap, n, xs))
  for it: S.Item
  for hi: D1.Elem(S.Item, it, D2.shard.items(s))
  for small: {Nat.is_le(rsize(D2.item.rec(it)), U32.to_nat(cap)) == True{} : Bool}
  Pair({item.from(it) == 1 : U32},
    {item.upto(it) == U32.from_nat(D2.rec.count(D2.item.rec(it))) : U32})

# LAW: Record.chars is a record's size
law chars_size:
  for r: R.Record
  {R.Record.chars(r) == U32.from_nat(rsize(r)) : U32}
