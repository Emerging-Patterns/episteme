import Base
import ../src/chat.bend as C
import ../src/honcho.bend as H

# LAW: an example: a cursor of count lines reads as counts, a line that is
# no entry is dropped, and set replaces an entry in place or adds one at
# the end
law hon_cursor_example:
  for u: Unit
  {C.Chat.cursor.set(C.Chat.cursor.set(
      H.Honcho.cursor("250\tclaude_code/projects\n250\thermes/noah\nbad line\n"),
      "claude_code/projects", 252), "w/s", 2)
    == [C.Seen{"claude_code/projects", 252}, C.Seen{"hermes/noah", 250},
      C.Seen{"w/s", 2}] : List<&2, C.Seen>}
