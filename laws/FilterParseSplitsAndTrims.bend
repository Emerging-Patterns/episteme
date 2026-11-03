import Base
import ../src/filter.bend as F

# LAW: an example: commas split a --filter value, each piece is trimmed of
# surrounding spaces, empty pieces are dropped, and a piece is a prefix
# only when it ends in /, not when a / is inside it.
law parse_example:
  for u: Unit
  {F.Filter.parse(["book:venaya/,,chat:honcho", "",
    "chat:claude/home-noah-projects-bend,", "a, b , "])
    == [F.Prefix{"book:venaya/"}, F.Exact{"chat:honcho"},
      F.Exact{"chat:claude/home-noah-projects-bend"}, F.Exact{"a"},
      F.Exact{"b"}]
    : List<&2, F.Sel>}
