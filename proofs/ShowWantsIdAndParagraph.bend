# proofs of laws/ShowWantsIdAndParagraph.bend
import Base
import ../src/cli.bend as Cl
import ../laws/ShowWantsIdAndParagraph.bend as Laws

def Laws.want_numbered(arg, id, num, n, cut, read):
  %Equal.sym(Maybe<&2, Cl.Cut>, Cl.Cli.cut.last(arg, '#'), Some{Cl.Cut{id, num}}, cut)
    : {Cl.Cli.want.cut(_, arg) == Cl.Want{id, Some{n}} : Cl.Want}
  %Equal.sym(Maybe<&2, U32>, U32.read(num), Some{n}, read)
    : {Cl.Cli.want.num(_, id, arg) == Cl.Want{id, Some{n}} : Cl.Want}
  {==}

def Laws.want_unnumbered(arg, id, num, cut, read):
  %Equal.sym(Maybe<&2, Cl.Cut>, Cl.Cli.cut.last(arg, '#'), Some{Cl.Cut{id, num}}, cut)
    : {Cl.Cli.want.cut(_, arg) == Cl.Want{arg, None{}} : Cl.Want}
  %Equal.sym(Maybe<&2, U32>, U32.read(num), None{}, read)
    : {Cl.Cli.want.num(_, id, arg) == Cl.Want{arg, None{}} : Cl.Want}
  {==}

def Laws.want_uncut(arg, cut):
  %Equal.sym(Maybe<&2, Cl.Cut>, Cl.Cli.cut.last(arg, '#'), None{}, cut)
    : {Cl.Cli.want.cut(_, arg) == Cl.Want{arg, None{}} : Cl.Want}
  {==}

def Laws.want_example(_u):
  {==}
