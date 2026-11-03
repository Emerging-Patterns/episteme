# proofs of laws/ToolRecordsInlineOrPoint.bend
import Base
import ../src/record.bend as R
import ../src/chat.bend as C
import ../laws/ToolRecordsInlineOrPoint.bend as Laws

def Laws.call_inline(ts, source, thread, parent, ptr, author, uuid, i, name, input, h):
  %Equal.sym(Bool, Nat.is_le(String.length(input), 4000n), True{}, h)
    : {C.Chat.call(_, ts, source, thread, parent, ptr, author, uuid, i, name, input)
      == R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
        thread, parent, name ++ "\n" ++ input, "") : Maybe<&2, R.Record>}
  {==}

def Laws.call_pointer(ts, source, thread, parent, ptr, author, uuid, i, name, input, h):
  %Equal.sym(Bool, Nat.is_le(String.length(input), 4000n), False{}, h)
    : {C.Chat.call(_, ts, source, thread, parent, ptr, author, uuid, i, name, input)
      == R.Record.make("claude:" ++ uuid ++ ":" ++ U32.show(i), ts, source, author,
        thread, parent,
        name ++ ", " ++ U32.show(U32.from_nat(String.length(input))) ++ " chars", ptr)
      : Maybe<&2, R.Record>}
  {==}

def Laws.back_pointer(_ts, _source, _thread, _parent, _ptr, _author, _uuid, _i, _chars):
  {==}
