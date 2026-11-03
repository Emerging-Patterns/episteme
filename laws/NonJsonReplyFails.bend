import Base
import ../src/read.bend as Rd
import ./defs/ReadOk.bend as D1

# LAW: an example: a body that is not JSON is a failed read
law reply_example_text:
  for u: Unit
  {D1.read.ok(Rd.Read.reply(4, "u", 200, "upstream error"))
    == False{} : Bool}
