import Base
import ../src/chat.bend as C

# LAW: an example: the complete lines of a text; what follows the last line
# feed is still being written
law lines_example:
  for u: Unit
  {[C.Chat.lines("a\nbc\n\nd"), C.Chat.lines(""), C.Chat.lines("x")]
    == [["a", "bc", ""], [], []] : List<&2, List<&2, String>>}
