# proofs of laws/MakeNeedsAParagraph.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../laws/MakeNeedsAParagraph.bend as Laws

# --- records ---

def Laws.make_empty(id, ts, source, author, thread, parent, body, ptr, h):
  %Equal.sym(List<&2, P.Para>, P.Para.split(body), [], h)
    : {R.Record.make.go(id, ts, source, author, thread, parent, _, ptr)
      == None{} : Maybe<&2, R.Record>}
  {==}

def Laws.make_some(
  id,
  ts,
  source,
  author,
  thread,
  parent,
  body,
  ptr,
  p,
  ps,
  h
):
  %Equal.sym(List<&2, P.Para>, P.Para.split(body), p <> ps, h)
    : {R.Record.make.go(id, ts, source, author, thread, parent, _, ptr)
      == Some{R.Record{id, ts, source, author, thread, parent, p <> ps, ptr}}
      : Maybe<&2, R.Record>}
  {==}
