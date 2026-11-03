# `Shard.dir(s)` of a non-empty source is not empty and holds no `/` or `.`,
# and `Shard.undir(Shard.dir(s)) == Some{s}`, so no two sources share a
# directory.
import Base
import ../src/shard.bend as S

# True when the code point chr is the text txt
def chr_is(chr: Char, txt: String) -> Bool:
  String.eq(SCon{chr, SNil{}}, txt)

# True when no code point of str is / or .
def plain(str: String) -> Bool:
  match str:
    case SNil{}:
      True{}
    case SCon{+c, t}:
      Bool.and(Bool.not(Bool.or(chr_is(c, "/"), chr_is(c, "."))), plain(t))

# LAW: a non-empty source's directory name is not empty and holds no / or
# .: a name of its own in the directory, never . or ..
law dir_safe:
  for +c: Char
  for +t: String
  Pair({String.is_empty(S.Shard.dir(SCon{c, t})) == False{} : Bool},
    {plain(S.Shard.dir(SCon{c, t})) == True{} : Bool})

# LAW: a directory name reads back as its source, so no two sources share
# one
law dir_round:
  for +src: String
  {S.Shard.undir(S.Shard.dir(src)) == Some{src} : Maybe<&2, String>}
