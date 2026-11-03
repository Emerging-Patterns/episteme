# Every frozen shard's `chars` is at most `cap`, for records with fewer than
# 2^32 paragraphs whose header line fits in `cap`, alone and beside any one of
# their paragraphs.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2

# a shard's size field
def shard.chars(sh: S.Shard) -> U32:
  match sh:
    case S.Shard{_n, _items, _sources, chars, _frozen}:
      chars

# each of ps fits in cap beside a header line of hlen code points
def roomy.paras(+cap: Nat, +hlen: Nat, ps: List<&2, P.Para>) -> Type:
  match ps:
    case Nil{}:
      Unit
    case Con{head, tail}:
      Pair({Nat.is_le(Nat.add(hlen, String.length(D2.para.text(head))), cap)
        == True{} : Bool}, roomy.paras(cap, hlen, tail))

# each record's header line fits in cap, alone and with any one of its
# paragraphs
def roomy(+cap: Nat, xs: List<&2, R.Record>) -> Type:
  match xs:
    case Nil{}:
      Unit
    case Con{+r, tail}:
      Pair({Nat.is_le(D2.rec.head(r), cap) == True{} : Bool},
        Pair(roomy.paras(cap, D2.rec.head(r), D2.rec.paras(r)), roomy(cap, tail)))

# LAW: every shard's size is at most cap, and its chars is that size; for
# records with fewer than 2^32 paragraphs whose header line fits in cap,
# alone and with any one of their paragraphs
law shard_size:
  for +cap: U32
  for +n: U32
  for +xs: List<&2, R.Record>
  for hc: D2.counted(xs)
  for hr: roomy(U32.to_nat(cap), xs)
  for s: S.Shard
  for hs: D1.Elem(S.Shard, s, S.Shard.pack(cap, n, xs))
  Pair({Nat.is_le(D2.size(D2.shard.items(s)), U32.to_nat(cap)) == True{} : Bool},
    {shard.chars(s) == U32.from_nat(D2.size(D2.shard.items(s))) : U32})
