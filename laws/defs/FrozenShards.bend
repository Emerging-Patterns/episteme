# which shards are frozen, and the shards the examples pack
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S

# whether a shard is frozen
def shard.frozen(sh: S.Shard) -> Bool:
  match sh:
    case S.Shard{_n, _items, _sources, _chars, frozen}:
      frozen

# s ahead of ss when it is frozen
def frozen.if(flag: Bool, sh: S.Shard, ss: List<&2, S.Shard>) -> List<&2, S.Shard>:
  match flag:
    case True{}:
      sh <> ss
    case False{}:
      ss

# the frozen shards of ss, in order
def frozen(ss: List<&2, S.Shard>) -> List<&2, S.Shard>:
  match ss:
    case Nil{}:
      []
    case Con{+s, tail}:
      frozen.if(shard.frozen(s), s, frozen(tail))

# a section of a book: a record with one paragraph of ten code points
def section(source: String, id: String) -> R.Record:
  R.Record{id, "t", source, "a", "", "", [P.Para{1, 0, 10, "0123456789"}], ""}

# each shard's sources and whether it is frozen
def sums(ss: List<&2, S.Shard>) -> List<&2, Sigma<&2, &2, List<&2, String>, _l => Bool>>:
  match ss:
    case Nil{}:
      []
    case Con{s, tail}:
      match s:
        case S.Shard{_n, _items, sources, _chars, frozen}:
          (sources, frozen) <> sums(tail)

# a frozen shard of two items: the second and third paragraphs of a
# record, then another record whole
def json_shard() -> S.Shard:
  S.Shard{3, [S.Item{R.Record{"m1", "2026-10-30T12:00:00.000Z",
      "chat:honcho", "noah", "", "", [P.Para{1, 0, 1, "a"},
      P.Para{2, 3, 4, "b"}, P.Para{3, 6, 9, "\"c\""}], ""}, 2, 3},
    S.Item{R.Record{"t9", "2026-10-30T12:00:01.250Z", "book:x/y", "", "",
      "", [P.Para{1, 0, 3, "dào"}], "file:/b.txt:3"}, 1, 1}],
    ["book:x/y", "chat:honcho"], 99, True{}}

# 1 for True, 0 for False
def flag(on: Bool) -> U32:
  match on:
    case True{}:
      1
    case False{}:
      0
