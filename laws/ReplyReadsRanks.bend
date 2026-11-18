import Base
import ../src/read.bend as Rd

# LAW: an example: a 200 whose content names two labels and their ranks is
# ok with both, and a rank that is no whole number reads as 0.
law reply_example_ranks:
  for u: Unit
  {[Rd.Read.reply(4, "u", 200,
      "{\"choices\":[{\"message\":{\"content\":\"{\\\"ids\\\":[\\\"p1\\\",\\\"p3\\\"],\\\"ranks\\\":[7,2]}\"}}]}"),
    Rd.Read.reply(4, "u", 200,
      "{\"choices\":[{\"message\":{\"content\":\"{\\\"ids\\\":[\\\"p1\\\",\\\"p3\\\"],\\\"ranks\\\":[\\\"x\\\",2]}\"}}]}")]
    == [Rd.Read{4, "u", ["p1", "p3"], [7, 2], True{}, "", 0, 0, 0, 0},
      Rd.Read{4, "u", ["p1", "p3"], [0, 2], True{}, "", 0, 0, 0, 0}]
    : List<&2, Rd.Read>}
