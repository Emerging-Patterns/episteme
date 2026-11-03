import Base
import ../src/chat.bend as C

# LAW: an example: what Chat.keep keeps
law keep_example:
  for u: Unit
  {[C.Chat.keep("{\"type\":\"user\",\"uuid\":\"u\"}"),
      C.Chat.keep("{\"parentUuid\":null,\"type\":\"assistant\"}"),
      C.Chat.keep("{\"type\":\"attachment\",\"attachment\":{\"type\":\"queued_command\"}}"),
      C.Chat.keep("{\"type\":\"api-request-blob\",\"blob\":\"{\\\"type\\\":\\\"user\\\"}\"}"),
      C.Chat.keep("{\"type\": \"user\"}")]
    == [True{}, True{}, True{}, False{}, False{}] : List<&2, Bool>}
