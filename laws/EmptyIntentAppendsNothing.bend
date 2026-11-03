# `Intent.records(last, "", ts)` is `[]` for every `last`: an empty file
# appends nothing.
import Base
import ../src/record.bend as R
import ../src/intent.bend as I

# LAW: an empty file gives no record, whatever was ingested before
law intent_empty:
  for last: String
  for ts: String
  {I.Intent.records(last, "", ts) == [] : List<&2, R.Record>}
