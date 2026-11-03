import Base
import ../src/chat.bend as C

# LAW: an example: a cursor reads back from its text, and set replaces an
# entry in place or adds one at the end
law cursor_example:
  for u: Unit
  {C.Chat.cursor(C.Chat.cursor.text(C.Chat.cursor.set(C.Chat.cursor.set(
      C.Chat.cursor("6\t-p/a.jsonl\n1\t-p/a/subagents/x.jsonl\n"),
      "-p/a.jsonl", 9), "-q/b.jsonl", 2)))
    == [C.Seen{"-p/a.jsonl", 9}, C.Seen{"-p/a/subagents/x.jsonl", 1},
      C.Seen{"-q/b.jsonl", 2}] : List<&2, C.Seen>}
