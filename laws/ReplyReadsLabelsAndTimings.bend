import Base
import ../src/read.bend as Rd

# LAW: an example: a 200 whose content names two labels is ok with them,
# its timings read in whole milliseconds.
law reply_example_ids:
  for u: Unit
  {Rd.Read.reply(4, "u", 200,
    "{\"choices\":[{\"message\":{\"content\":\"{\\\"ids\\\":[\\\"p1\\\",\\\"p3\\\"]}\"}}],\"timings\":{\"prompt_n\":12,\"prompt_ms\":3.5,\"cache_n\":2,\"predicted_ms\":1.9}}")
    == Rd.Read{4, "u", ["p1", "p3"], True{}, "", 12, 3, 2, 4} : Rd.Read}
