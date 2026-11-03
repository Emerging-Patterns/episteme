import Base
import ../src/chat.bend as C

# LAW: an example: UTF-8 of one to four bytes, then a byte that is no
# lead, a sequence cut short, a continuation byte alone and an overlong
# line feed, each one U+FFFD
law utf8_example:
  for u: Unit
  {C.Chat.utf8([104, 195, 169, 226, 130, 172, 240, 159, 152, 128, 10, 255, 226, 130, 10, 224, 128, 138])
    == "hé€😀\n���\n�" : String}
