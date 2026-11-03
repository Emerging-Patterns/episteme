import Base
import ../src/chat.bend as C

# LAW: an example: a claude cursor of an older entry, an entry with bytes
# and a line that is neither reads back from its text, and set replaces
# an entry in place or adds one at the end
law ats_example:
  for u: Unit
  {C.Chat.ats(C.Chat.ats.text(C.Chat.at.set(C.Chat.at.set(
      C.Chat.ats("6\t-p/a.jsonl\n9\t120\t-p/b.jsonl\nbad\n2\t-q/c.jsonl\n"),
      C.At{"-p/a.jsonl", 7, Some{300}}), C.At{"-q/d.jsonl", 1, Some{5}})))
    == [C.At{"-p/a.jsonl", 7, Some{300}}, C.At{"-p/b.jsonl", 9, Some{120}},
      C.At{"-q/c.jsonl", 2, None{}}, C.At{"-q/d.jsonl", 1, Some{5}}] : List<&2, C.At>}
