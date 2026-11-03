import Base
import ../src/shard.bend as S

# LAW: an example: a chat source's directory name
law dir_chat:
  for u: Unit
  {S.Shard.dir("chat:claude/home-noah-projects-bend")
    == "chat:claude%2Fhome-noah-projects-bend" : String}
