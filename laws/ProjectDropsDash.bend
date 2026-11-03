# `Chat.project` drops the leading `-` of a project directory's name:
# `-home-noah-x` is the project `home-noah-x`.
import Base
import ../src/chat.bend as C

# LAW: a project's name is its directory's name without the leading dash
law project_dash:
  for dir: String
  {C.Chat.project(SCon{'-', dir}) == dir : String}
