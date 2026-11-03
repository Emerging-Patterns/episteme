# proofs of laws/SourceDirsAreSafeAndDistinct.bend
import Base
import ../src/shard.bend as S
import ../laws/SourceDirsAreSafeAndDistinct.bend as Laws
import ./lemmas/TextOrder.bend as M1

# a code point's directory name is not empty
def dir_ne(
  p: Bool,
  sl: Bool,
  d: Bool,
  -c: Char,
  -r: String
) -> {String.is_empty(S.Shard.dir.ch(p, sl, d, c, r)) == False{} : Bool}:
  match p sl d:
    case True{} _ _:
      {==}
    case False{} True{} _:
      {==}
    case False{} False{} True{}:
      {==}
    case False{} False{} False{}:
      {==}

# a code point's directory name holds no / or . when the rest's holds none
def plain_ch(
  p: Bool,
  sl: Bool,
  d: Bool,
  +c: Char,
  -r: String,
  es: {S.Shard.is(c, "/") == sl : Bool},
  ed: {S.Shard.is(c, ".") == d : Bool},
  ih: {Laws.plain(r) == True{} : Bool}
) -> {Laws.plain(S.Shard.dir.ch(p, sl, d, c, r)) == True{} : Bool}:
  match p sl d:
    case True{} _ _:
      ih
    case False{} True{} _:
      ih
    case False{} False{} True{}:
      ih
    case False{} False{} False{}:
      %Equal.sym(Bool, S.Shard.is(c, "/"), False{}, es)
        : {Bool.and(Bool.not(Bool.or(_, S.Shard.is(c, "."))), Laws.plain(r)) == True{} : Bool}
      %Equal.sym(Bool, S.Shard.is(c, "."), False{}, ed)
        : {Bool.and(Bool.not(Bool.or(False{}, _)), Laws.plain(r)) == True{} : Bool}
      ih

# no source's directory name holds / or .
law plain_dir:
  for +t: String
  {Laws.plain(S.Shard.dir(t)) == True{} : Bool}

def plain_dir(t):
  match t:
    case SNil{}:
      {==}
    case SCon{+c, +rest}:
      plain_ch(S.Shard.is(c, "%"), S.Shard.is(c, "/"), S.Shard.is(c, "."), c,
        S.Shard.dir(rest), {==}, {==}, plain_dir(rest))

# laws/SourceDirsAreSafeAndDistinct.bend: a non-empty source's name is not empty and holds no / or .
def Laws.dir_safe(c, t):
  (dir_ne(S.Shard.is(c, "%"), S.Shard.is(c, "/"), S.Shard.is(c, "."), c, S.Shard.dir(t)),
    plain_dir(SCon{c, t}))
