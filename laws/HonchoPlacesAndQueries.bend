import Base
import ../src/honcho.bend as H

# LAW: an example: the places and queries of counts 0, 100 and 250
law hon_place_example:
  for u: Unit
  {(H.Honcho.place(0n), H.Honcho.place(100n), H.Honcho.place(250n), H.Honcho.query(2n))
    == (H.Place{0n, 0n}, H.Place{1n, 0n}, H.Place{2n, 50n}, "?page=3&size=100")
    : H.Place & H.Place & H.Place & String}
