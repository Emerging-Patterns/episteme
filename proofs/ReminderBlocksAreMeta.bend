# proofs of laws/ReminderBlocksAreMeta.bend
import Base
import ../src/chat.bend as C
import ../laws/ReminderBlocksAreMeta.bend as Laws

def Laws.plain_text_is_said(text, plain):
  %Equal.sym(Bool, String.starts_with(text, "<system-reminder>"), False{}, plain)
    : {C.Chat.parts.if(_, text) == [C.Said{text}] : List<&2, C.Block>}
  {==}

def Laws.note_is_metas_record(_ts, _source, _thread, _parent, _ptr, _author, _uuid, _i, _text):
  {==}

def Laws.note_is_not_said(_text, _rest):
  {==}

def Laws.other_lines_keep_their_blocks(_blocks):
  {==}

def Laws.mine_keeps_other_blocks(_name, _input, _chars, _rest):
  {==}

def Laws.read_reminder_example(_u):
  {==}
