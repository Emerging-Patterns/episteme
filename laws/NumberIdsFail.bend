import Base
import ../src/read.bend as Rd
import ./defs/ReadOk.bend as D1

# LAW: an example: ids that are not strings make a failed read
law reply_example_number:
  for u: Unit
  {D1.read.ok(Rd.Read.reply(4, "u", 200,
    "{\"choices\":[{\"message\":{\"content\":\"{\\\"ids\\\":[1]}\"}}]}"))
    == False{} : Bool}
