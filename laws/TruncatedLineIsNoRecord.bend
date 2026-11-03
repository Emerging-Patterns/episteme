import Base
import ../src/record.bend as R

# LAW: an example: a line cut short reads as no record
law line_truncated:
  for u: Unit
  {R.Record.of_line("{\"id\":\"m1\",\"ts\":\"2026-10-30T12:00:00.000Z\",\"source\":\"chat:honcho\",\"author\":\"noah\",\"thread\":\"\",\"parent\":\"\",\"paras\":[[1,0,5,\"hel")
    == None{} : Maybe<&2, R.Record>}
