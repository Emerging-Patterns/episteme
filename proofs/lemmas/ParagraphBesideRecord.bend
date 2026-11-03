# a paragraph beside its record among the items
import Base
import ../../src/shard.bend as S
import ../../laws/ResolveKeepsNamedParagraphs.bend as L1
import ../../laws/defs/ListMembership.bend as D1

# a paragraph beside its record among xs, with record id id and number n
def got(-id: String, -n: U32, xs: List<&2, S.Shard.Line()>) -> Type:
  Exists(S.Shard.Line(), line => Pair(D1.Elem(S.Shard.Line(), line, xs),
    Pair({L1.ln.id(line) == id : String}, {L1.ln.n(line) == n : U32})))
