import Base
import ../src/read.bend as Rd

# LAW: an example: a 200 whose content names no labels is ok and empty
law reply_example_empty:
  for u: Unit
  {Rd.Read.reply(4, "u", 200,
    "{\"choices\":[{\"message\":{\"content\":\"{\\\"ids\\\":[]}\"}}]}")
    == Rd.Read{4, "u", [], True{}, "", 0, 0, 0, 0} : Rd.Read}
