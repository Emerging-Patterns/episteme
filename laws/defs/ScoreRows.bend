# a score row's gold spans and those recalled
import Base
import ../../src/score.bend as Sc

# a row's gold recalled
def row.hit(row: Sc.Row) -> Nat:
  match row:
    case Sc.Row{_id, hit, _gold, _chars, _unknown, _failed, _ms, _pn, _pm, _cv, _sp}:
      hit

# a row's gold
def row.gold(row: Sc.Row) -> Nat:
  match row:
    case Sc.Row{_id, _hit, gold, _chars, _unknown, _failed, _ms, _pn, _pm, _cv, _sp}:
      gold
