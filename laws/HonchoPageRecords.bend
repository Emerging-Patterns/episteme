import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/honcho.bend as H
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# the records of a page's JSON text, none when it has no items array
def hon.page(text: String) -> List<&2, R.Record>:
  H.Honcho.records(H.Honcho.msgs(Maybe.default(&2, List<&2, Value.Json>,
    H.Honcho.items(text), [])))

# LAW: an example: of a page's three messages, the one with its fields is a
# record; one lacking peer_id and one with empty content are none
law hon_page_example:
  for u: Unit
  {hon.page("{\"items\":[{\"id\":\"m1\",\"content\":\"one\\n\\ntwo\",\"peer_id\":\"noah\",\"session_id\":\"s1\",\"metadata\":{},\"created_at\":\"2026-03-11T18:25:58.787375Z\",\"workspace_id\":\"w\",\"token_count\":2},{\"id\":\"m2\",\"content\":\"x\",\"session_id\":\"s1\",\"created_at\":\"2026-03-11T18:25:59.000000Z\",\"workspace_id\":\"w\"},{\"id\":\"m3\",\"content\":\"\",\"peer_id\":\"claude\",\"session_id\":\"s1\",\"created_at\":\"2026-03-11T18:26:00.000000Z\",\"workspace_id\":\"w\"}],\"total\":3,\"page\":1,\"size\":100,\"pages\":1}")
    == [R.Record{"honcho:m1", "2026-03-11T18:25:58.787375Z", "chat:honcho", "noah",
      "w/s1", "", [P.Para{1, 0, 3, "one"}, P.Para{2, 5, 8, "two"}], ""}]
    : List<&2, R.Record>}
