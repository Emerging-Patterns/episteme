import Base
import ../src/read.bend as Rd
import ./defs/ReadOk.bend as D1

# LAW: an example: a 400 is a failed read, even with a good body
law reply_example_status:
  for u: Unit
  {D1.read.ok(Rd.Read.reply(4, "u", 400,
    "{\"choices\":[{\"message\":{\"content\":\"{\\\"ids\\\":[]}\"}}]}"))
    == False{} : Bool}
