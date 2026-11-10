# proofs of laws/GroupsKeepEveryParagraph.bend
import Base
import ../src/para.bend as P
import ../laws/GroupsKeepEveryParagraph.bend as Laws
import ./lemmas/BoolFacts.bend as M1

# joining a paragraph to groups puts it ahead of what they hold
def join_keep(
  new: Bool,
  +para: P.Para,
  gs: List<&2, List<&2, P.Para>>
) -> {List.concat(&2, P.Para, P.Para.join(new, para, gs))
    == para <> List.concat(&2, P.Para, gs) : List<&2, P.Para>}:
  match new:
    case True{}:
      {==}
    case False{}:
      match gs:
        case Nil{}:
          {==}
        case Con{_group, _rest}:
          {==}

def Laws.groups_keep(ps, cap, used):
  match ps:
    case Nil{}:
      {==}
    case Con{+para, +rest}:
      +size = Nat.add(used, P.Para.size(para))
      +full = Nat.is_le(cap, size)
      +gs = P.Para.groups(rest, cap, P.Para.held(full, size))
      Equal.trans(List<&2, P.Para>,
        List.concat(&2, P.Para, P.Para.join(full, para, gs)),
        para <> List.concat(&2, P.Para, gs), para <> rest,
        join_keep(full, para, gs),
        Equal.cong(List<&2, P.Para>, List<&2, P.Para>, x => para <> x,
          List.concat(&2, P.Para, gs), rest,
          Laws.groups_keep(rest, cap, P.Para.held(full, size))))

# joining a paragraph to groups none of which is empty leaves none empty
def join_filled(
  new: Bool,
  +para: P.Para,
  gs: List<&2, List<&2, P.Para>>,
  h: {Laws.filled(gs) == True{} : Bool}
) -> {Laws.filled(P.Para.join(new, para, gs)) == True{} : Bool}:
  match new:
    case True{}:
      h
    case False{}:
      match gs:
        case Nil{}:
          {==}
        case Con{group, rest}:
          match group:
            case Nil{}:
              Empty.absurd({Laws.filled(rest) == True{} : Bool}, M1.clash(h))
            case Con{_first, _more}:
              h

def Laws.groups_filled(ps, cap, used):
  match ps:
    case Nil{}:
      {==}
    case Con{+para, +rest}:
      +size = Nat.add(used, P.Para.size(para))
      +full = Nat.is_le(cap, size)
      join_filled(full, para, P.Para.groups(rest, cap, P.Para.held(full, size)),
        Laws.groups_filled(rest, cap, P.Para.held(full, size)))
