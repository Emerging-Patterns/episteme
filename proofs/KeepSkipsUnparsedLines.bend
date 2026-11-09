# proofs of laws/KeepSkipsUnparsedLines.bend
import Base
import ../src/record.bend as R
import ../src/chat.bend as C
import ezjson@1.2.0.0/main.bend as Json
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
