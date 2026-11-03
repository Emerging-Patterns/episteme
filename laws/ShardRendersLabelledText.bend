import Base
import ../src/shard.bend as S
import ./defs/FrozenShards.bend as D1

# LAW: an example: a shard's reader text, each item's header line and then
# its paragraphs labelled across the shard, items apart by a blank line
law render_example:
  for u: Unit
  {S.Shard.render(D1.json_shard())
    == "== chat:honcho | 2026-10-30T12:00:00.000Z | noah | m1\n[p1] b\n[p2] \"c\"\n\n== book:x/y | 2026-10-30T12:00:01.250Z |  | t9\n[p3] dào\n"
    : String}
