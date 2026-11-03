# `Chat.cut(bs)` is 0 for bytes with no line feed and otherwise the bytes up
# to and with the last one, so the claude connector's next read starts right
# after its last complete line; `Chat.from` reads on from an entry's bytes
# with nothing to skip, and reads an entry an older cursor wrote with lines
# alone from byte 0, skipping its lines.
#
# The claude connector reads each transcript on from a byte
# (src/conn/claude.bend). Its cursor holds one entry `At{file, lines,
# bytes}` per transcript: the complete lines read and the bytes they take,
# written `<lines>\t<bytes>\t<file>`. An entry a cursor before byte offsets
# wrote, `<lines>\t<file>`, reads with no bytes: a line is the new kind when
# the text after its first tab is a number, a tab and a non-empty file, and
# a transcript's path begins with its project directory's `-`, so an older
# line is never misread. `Chat.from(at)` says where a read starts: an entry
# with bytes reads on from them and skips nothing; one without reads from
# byte 0 and skips its lines, so an older cursor gives the lines it gave
# before. `Chat.cut(bs)` is the bytes of `bs` up to and with its last line
# feed. `Chat.after(at, bs, path, project)` reads `bs`, the bytes from where
# `Chat.from` says, as UTF-8 with `Chat.utf8`, takes their complete lines
# with `Chat.lines`, and gives the records of those past the skip, numbered
# on from the lines before them, and the entry after: its lines plus those
# read, at its byte plus `Chat.cut(bs)`. `Chat.utf8` reads a broken or
# cut-short sequence, an overlong one, a surrogate or a code point past
# U+10FFFF as one U+FFFD and goes on at the byte after its lead; a
# continuation byte is never a line feed and no sequence decodes to one, so
# the line feeds of the text are those of the bytes, and the lines
# `Chat.lines` takes are the lines `Chat.cut` ends. Closed examples check
# `Chat.utf8` on one- to four-byte sequences and four broken ones
# (laws/Utf8ReadsAndReplaces.bend), `Chat.after` from an entry with bytes
# and from an older one (laws/AfterReadsOnFromCursor.bend), and the cursor
# text (laws/ClaudeCursorReadsBack.bend); no guarantee rests on them.
# Trusted, not proved: `Chat.utf8` reads every valid UTF-8 text as Base's
# file read does; on a copy of the live store the records it gave matched
# the line-count connector's byte for byte.
import Base
import ../src/chat.bend as C

# True when no byte of bs is a line feed
def feedless(bs: List<&2, U32>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case Con{b, rest}:
      Bool.and(Bool.not(U32.is_eq(b, 10)), feedless(rest))

# LAW: bytes with no line feed have no complete line
law cut_none:
  for +ys: List<&2, U32>
  for h: {feedless(ys) == True{} : Bool}
  {C.Chat.cut(ys) == 0n : Nat}

# LAW: the complete lines of bytes end with their last line feed: a read
# goes on at the byte after it
law cut_last:
  for +xs: List<&2, U32>
  for +ys: List<&2, U32>
  for h: {feedless(ys) == True{} : Bool}
  {C.Chat.cut(List.append(&2, U32, xs, 10 <> ys)) == 1n+List.length(&2, U32, xs) : Nat}

# LAW: an entry with its bytes reads on from them, with nothing to skip
law from_bytes:
  for file: String
  for lines: U32
  for bytes: U32
  {C.Chat.from(C.At{file, lines, Some{bytes}}) == C.From{bytes, lines, 0} : C.From}

# LAW: an entry an older cursor wrote, lines alone, reads from byte 0 and
# skips its lines
law from_lines:
  for file: String
  for lines: U32
  {C.Chat.from(C.At{file, lines, None{}}) == C.From{0, 0, lines} : C.From}
