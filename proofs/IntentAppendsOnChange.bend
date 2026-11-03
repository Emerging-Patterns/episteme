# proofs of laws/IntentAppendsOnChange.bend
import Base
import ../src/record.bend as R
import ../src/intent.bend as I
import ../laws/IntentAppendsOnChange.bend as Laws
import ./lemmas/PackingSteps.bend as M1

def Laws.intent_same(text, ts):
  %Equal.sym(Bool, String.eq(text, text), True{}, M1.eq_refl(text))
    : {I.Intent.records.if(_, text, ts) == [] : List<&2, R.Record>}
  {==}

def Laws.intent_changed(last, text, ts, h):
  %Equal.sym(Bool, String.eq(last, text), False{}, h)
    : {I.Intent.records.if(_, text, ts)
      == I.Intent.list(R.Record.make("intent@" ++ ts, ts, "intent", "noah", "", "", text, ""))
      : List<&2, R.Record>}
  {==}
