# `Para.groups(ps, cap, used)` cuts the paragraphs `ps` into consecutive
# groups, closing a group after the paragraph that brings its texts to `cap`
# code points or more: the books connector makes one record of each group of
# a span, so a book with no heading inside a long stretch is not one record
# as long as the stretch. The groups, joined in order, are `ps`: no
# paragraph is lost, repeated, changed or moved. No group is empty.
import Base
import ../src/para.bend as P

# True when no group of gs is empty
def filled(gs: List<&2, List<&2, P.Para>>) -> Bool:
  match gs:
    case Nil{}:
      True{}
    case Con{group, rest}:
      match group:
        case Nil{}:
          False{}
        case Con{_para, _more}:
          filled(rest)

# LAW: the groups of ps, joined in order, are ps, whatever the cap and
# whatever the open group already holds
law groups_keep:
  for ps: List<&2, P.Para>
  for +cap: Nat
  for +used: Nat
  {List.concat(&2, P.Para, P.Para.groups(ps, cap, used)) == ps : List<&2, P.Para>}

# LAW: no group of ps is empty, whatever the cap and whatever the open
# group already holds
law groups_filled:
  for ps: List<&2, P.Para>
  for +cap: Nat
  for +used: Nat
  {filled(P.Para.groups(ps, cap, used)) == True{} : Bool}
