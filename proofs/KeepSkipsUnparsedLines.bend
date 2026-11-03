# proofs of laws/KeepSkipsUnparsedLines.bend
import Base
import ../src/record.bend as R
import ../src/chat.bend as C
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import ../laws/KeepSkipsUnparsedLines.bend as Laws

def Laws.keep_drop(path, project, n, text, h):
  %Equal.sym(Bool, C.Chat.keep(text), False{}, h)
    : {C.Chat.read.if(_, path, project, n, text) == [] : List<&2, R.Record>}
  {==}

def Laws.keep_read(path, project, n, text, h):
  %Equal.sym(Bool, C.Chat.keep(text), True{}, h)
    : {C.Chat.read.if(_, path, project, n, text)
      == C.Chat.parsed(path, project, n, Json.parse(text)) : List<&2, R.Record>}
  {==}
