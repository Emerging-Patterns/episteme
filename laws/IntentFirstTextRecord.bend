import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/intent.bend as I

# LAW: an example: a first text is one record of its paragraphs
law intent_example:
  for u: Unit
  {I.Intent.records("", "Ship it.\n\nThen rest.\n", "2026-10-31T12:00:00.000Z")
    == [R.Record{"intent@2026-10-31T12:00:00.000Z", "2026-10-31T12:00:00.000Z", "intent",
      "noah", "", "", [P.Para{1, 0, 8, "Ship it."}, P.Para{2, 10, 20, "Then rest."}], ""}]
    : List<&2, R.Record>}
