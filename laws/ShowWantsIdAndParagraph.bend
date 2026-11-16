# `episteme show <arg>` (and the `show` tool) wants a record and, maybe, one
# paragraph of it: `Cli.want(arg)` cuts `arg` at its last `#`
# (`Cli.cut.last`). When the text after it reads as a number `n`, the id is
# the text before it and the paragraph is `n`; when it does not read, or
# `arg` has no `#`, the id is the whole argument and every paragraph is
# wanted. So an id that itself holds a `#` is still shown whole, and only the
# last `#` can name a paragraph.
import Base
import ../src/cli.bend as Cl

# LAW: a number after the last `#` names the paragraph of the id before it
law want_numbered:
  for +arg: String
  for +id: String
  for +num: String
  for +n: U32
  for cut: {Cl.Cli.cut.last(arg, '#') == Some{Cl.Cut{id, num}} : Maybe<&2, Cl.Cut>}
  for read: {U32.read(num) == Some{n} : Maybe<&2, U32>}
  {Cl.Cli.want(arg) == Cl.Want{id, Some{n}} : Cl.Want}

# LAW: text after the last `#` that is no number leaves the argument whole
law want_unnumbered:
  for +arg: String
  for +id: String
  for +num: String
  for cut: {Cl.Cli.cut.last(arg, '#') == Some{Cl.Cut{id, num}} : Maybe<&2, Cl.Cut>}
  for read: {U32.read(num) == None{} : Maybe<&2, U32>}
  {Cl.Cli.want(arg) == Cl.Want{arg, None{}} : Cl.Want}

# LAW: an argument with no `#` is the whole id
law want_uncut:
  for +arg: String
  for cut: {Cl.Cli.cut.last(arg, '#') == None{} : Maybe<&2, Cl.Cut>}
  {Cl.Cli.want(arg) == Cl.Want{arg, None{}} : Cl.Want}

# LAW: an example: only the last `#` names a paragraph
law want_example:
  for u: Unit
  {[Cl.Cli.want("claude:abc#3"), Cl.Cli.want("a#b#12"), Cl.Cli.want("a#b"), Cl.Cli.want("ab")]
    == [Cl.Want{"claude:abc", Some{3}}, Cl.Want{"a#b", Some{12}}, Cl.Want{"a#b", None{}},
      Cl.Want{"ab", None{}}]
    : List<&2, Cl.Want>}
