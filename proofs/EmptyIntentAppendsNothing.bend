# proofs of laws/EmptyIntentAppendsNothing.bend
import Base
import ../src/record.bend as R
import ../src/intent.bend as I
import ../laws/EmptyIntentAppendsNothing.bend as Laws

# an empty text gives no record, whether or not it was the last
def intent_empty.if(b: Bool, -ts: String) -> {I.Intent.records.if(b, "", ts) == [] : List<&2, R.Record>}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.intent_empty(last, ts):
  intent_empty.if(String.eq(last, ""), ts)
