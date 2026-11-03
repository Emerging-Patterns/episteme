# `Chat.read(path, project, n, text)` is none when `Chat.keep(text)` is
# False, without parsing it, and the records of `Json.parse(text)`
# (`Chat.parsed`) when it is True.
#
# `Chat.keep(text)` is True when a line holds `"type":"user"`,
# `"type":"assistant"` or `queued_command` as written, and `Chat.read`
# parses only a line it keeps. Claude Code writes its JSON compact, so every
# line `Chat.decode` reads holds one of them, while 44% of transcript bytes
# (`api-request-blob`, `api-request` and most `attachment` lines) hold none
# and are dropped unparsed. Trusted, not proved: no line Claude Code writes
# spells its type with a space after the colon; such a line would be
# dropped, and that is about the writer, which no law reaches. A closed
# example checks five lines (laws/KeepPicksMessageLines.bend).
import Base
import ../src/record.bend as R
import ../src/chat.bend as C
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json

# LAW: a line Chat.keep drops makes no record
law keep_drop:
  for path: String
  for project: String
  for n: U32
  for +text: String
  for h: {C.Chat.keep(text) == False{} : Bool}
  {C.Chat.read(path, project, n, text) == [] : List<&2, R.Record>}

# LAW: a line Chat.keep keeps makes the records of its JSON
law keep_read:
  for path: String
  for project: String
  for n: U32
  for +text: String
  for h: {C.Chat.keep(text) == True{} : Bool}
  {C.Chat.read(path, project, n, text)
    == C.Chat.parsed(path, project, n, Json.parse(text)) : List<&2, R.Record>}
