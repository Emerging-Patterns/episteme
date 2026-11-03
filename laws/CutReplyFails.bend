import Base
import ../src/read.bend as Rd
import ./defs/ReadOk.bend as D1

# LAW: an example: content cut short at max_tokens is a failed read
law reply_example_cut:
  for u: Unit
  {D1.read.ok(Rd.Read.reply(4, "u", 200,
    "{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"content\":\"{\\\"ids\\\":[\\\"p1\\\",\"}}]}"))
    == False{} : Bool}
