import Base
import ../src/record.bend as R

# LAW: an example: a paragraph of five elements reads as no record
law line_long_para:
  for u: Unit
  {R.Record.of_line("{\"id\":\"m1\",\"ts\":\"2026-10-30T12:00:00.000Z\",\"source\":\"chat:honcho\",\"author\":\"noah\",\"thread\":\"\",\"parent\":\"\",\"paras\":[[1,0,5,\"hello\",7]],\"ptr\":\"\"}")
    == None{} : Maybe<&2, R.Record>}
