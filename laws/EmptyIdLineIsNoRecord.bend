import Base
import ../src/record.bend as R

# LAW: an example: a line with an empty id reads as no record
law line_empty_id:
  for u: Unit
  {R.Record.of_line("{\"id\":\"\",\"ts\":\"2026-10-30T12:00:00.000Z\",\"source\":\"chat:honcho\",\"author\":\"noah\",\"thread\":\"\",\"parent\":\"\",\"paras\":[[1,0,5,\"hello\"]],\"ptr\":\"\"}")
    == None{} : Maybe<&2, R.Record>}
