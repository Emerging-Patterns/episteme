# proofs of laws/GitCutFits.bend
import Base
import ../src/git.bend as G
import ../laws/GitCutFits.bend as Laws
import ./lemmas/BoolFacts.bend as M1

# u + c is at most left when u is, and c is at most left less u
def le_sub_add(
  +u: Nat,
  +left: Nat,
  -c: Nat,
  e1: {Nat.is_le(u, left) == True{} : Bool},
  e2: {Nat.is_le(c, Nat.sub(left, u)) == True{} : Bool}
) -> {Nat.is_le(Nat.add(u, c), left) == True{} : Bool}:
  match u left:
    case 0n 0n:
      e2
    case 0n 1n+_q:
      e2
    case 1n+_p 0n:
      Empty.absurd({Nat.is_le(Nat.add(u, c), left) == True{} : Bool}, M1.clash(e1))
    case 1n+p 1n+q:
      le_sub_add(p, q, c, e1, e2)

# the code points a cut with a line kept ahead keeps are the line's, with
# its line feed, and those of the cut
def git_keep_used(
  -line: String,
  cut: G.Kept
) -> {Laws.git.used(Laws.git.kept(G.Git.keep(line, cut)))
    == Nat.add(Nat.add(String.length(line), 1n), Laws.git.used(Laws.git.kept(cut))) : Nat}:
  match cut:
    case G.Kept{_kept, _rest}:
      {==}

# the lines a cut keeps fit in what is left after the line
def git_fit.rest(cut: G.Kept, line: String, left: Nat) -> Type:
  {Nat.is_le(Laws.git.used(Laws.git.kept(cut)), Nat.sub(left, Nat.add(String.length(line), 1n))) == True{} : Bool}

# one step of a cut keeps lines that fit, when the rest of the cut keeps
# lines that fit in what is left after the line
def git_fit.step(
  b: Bool,
  +line: String,
  -rest: List<&2, String>,
  more: Unit -> G.Kept,
  +left: Nat,
  eb: {Nat.is_le(Nat.add(String.length(line), 1n), left) == b : Bool},
  ih: git_fit.rest(more(Unit{}), line, left)
) -> {Nat.is_le(Laws.git.used(Laws.git.kept(G.Git.cut.if(b, line, rest, more))), left)
    == True{} : Bool}:
  match b:
    case True{}:
      %Equal.sym(Nat, Laws.git.used(Laws.git.kept(G.Git.keep(line, more(Unit{})))),
        Nat.add(Nat.add(String.length(line), 1n), Laws.git.used(Laws.git.kept(more(Unit{})))),
        git_keep_used(line, more(Unit{})))
        : {Nat.is_le(_, left) == True{} : Bool}
      le_sub_add(Nat.add(String.length(line), 1n), left,
        Laws.git.used(Laws.git.kept(more(Unit{}))), eb, ih)
    case False{}:
      M1.zero_le(left)

# the lines a cut keeps fit in what it was left
def git_fit(
  lines: List<&2, String>,
  +left: Nat
) -> {Nat.is_le(Laws.git.used(Laws.git.kept(G.Git.cut(lines, left))), left) == True{} : Bool}:
  match lines:
    case Nil{}:
      M1.zero_le(left)
    case Con{+line, +rest}:
      git_fit.step(Nat.is_le(Nat.add(String.length(line), 1n), left), line, rest,
        _u => G.Git.cut(rest, Nat.sub(left, Nat.add(String.length(line), 1n))), left, {==},
        git_fit(rest, Nat.sub(left, Nat.add(String.length(line), 1n))))

def Laws.git_fit(lines, left):
  git_fit(lines, left)
