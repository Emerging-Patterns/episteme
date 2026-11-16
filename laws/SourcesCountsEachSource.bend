# `episteme sources` (and the `sources` tool) prints one line per source,
# `<source> <records> <paragraphs> <shards>` (`Cli.stat.lines`), from one
# `Stat` per source kept in source order (`Cli.stat.put`): a source not yet
# counted gets a new `Stat` at its place, and one already counted gets the
# counts added. Each item of a shard adds, to its record's source, one
# record when it holds the record's paragraph 1 (`Cli.first`), and its
# paragraphs (`Cli.stat.items`); each shard adds one shard to every source
# it holds (`Cli.stat.sources`, `Cli.stat.shards`). A shard that was not
# read is counted by what its source's size file holds (`Cli.stat.light`).
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/cli.bend as Cl

# LAW: an item holding its record's paragraph 1 counts one record
law first_opens:
  for start: U32
  for end: U32
  for text: String
  for rest: List<&2, P.Para>
  {Cl.Cli.first(P.Para{1, start, end, text} <> rest) == 1 : U32}

# LAW: an item opening on a later paragraph counts no record
law first_later:
  for +k: U32
  for start: U32
  for end: U32
  for text: String
  for rest: List<&2, P.Para>
  for h: {U32.is_eq(k, 1) == False{} : Bool}
  {Cl.Cli.first(P.Para{k, start, end, text} <> rest) == 0 : U32}

# LAW: an item with no paragraphs counts no record
law first_none:
  for u: Unit
  {Cl.Cli.first([]) == 0 : U32}

# LAW: the first source counted is the only line
law put_new:
  for +src: String
  for +recs: U32
  for +ps: U32
  for +shs: U32
  {Cl.Cli.stat.put([], src, recs, ps, shs) == [Cl.Stat{src, recs, ps, shs}] : List<&2, Cl.Stat>}

# LAW: a source already counted gets the counts added, in place
law put_same:
  for +src: String
  for +source: String
  for +records: U32
  for +paras: U32
  for +shards: U32
  for +rest: List<&2, Cl.Stat>
  for +recs: U32
  for +ps: U32
  for +shs: U32
  for h: {String.order(src, source) == EQ{} : Cmp}
  {Cl.Cli.stat.put(Cl.Stat{source, records, paras, shards} <> rest, src, recs, ps, shs)
    == Cl.Stat{source, U32.add(records, recs), U32.add(paras, ps), U32.add(shards, shs)} <> rest
    : List<&2, Cl.Stat>}

# LAW: a source before the first counted one goes ahead of it
law put_before:
  for +src: String
  for +source: String
  for +records: U32
  for +paras: U32
  for +shards: U32
  for +rest: List<&2, Cl.Stat>
  for +recs: U32
  for +ps: U32
  for +shs: U32
  for h: {String.order(src, source) == LT{} : Cmp}
  {Cl.Cli.stat.put(Cl.Stat{source, records, paras, shards} <> rest, src, recs, ps, shs)
    == Cl.Stat{src, recs, ps, shs} <> Cl.Stat{source, records, paras, shards} <> rest
    : List<&2, Cl.Stat>}

# LAW: a source after the first counted one goes among the rest
law put_after:
  for +src: String
  for +source: String
  for +records: U32
  for +paras: U32
  for +shards: U32
  for +rest: List<&2, Cl.Stat>
  for +recs: U32
  for +ps: U32
  for +shs: U32
  for h: {String.order(src, source) == GT{} : Cmp}
  {Cl.Cli.stat.put(Cl.Stat{source, records, paras, shards} <> rest, src, recs, ps, shs)
    == Cl.Stat{source, records, paras, shards} <> Cl.Cli.stat.put(rest, src, recs, ps, shs)
    : List<&2, Cl.Stat>}

# LAW: an item adds its record and paragraphs to its record's source
law items_one:
  for +id: String
  for +ts: String
  for +source: String
  for +author: String
  for +thread: String
  for +parent: String
  for +paras: List<&2, P.Para>
  for +ptr: String
  for +from: U32
  for +upto: U32
  for +rest: List<&2, S.Item>
  for +sts: List<&2, Cl.Stat>
  {Cl.Cli.stat.items(S.Item{R.Record{id, ts, source, author, thread, parent, paras, ptr}, from, upto} <> rest,
      sts)
    == Cl.Cli.stat.items(rest, Cl.Cli.stat.put(sts, source,
      Cl.Cli.first(S.Shard.item.paras(S.Item{R.Record{id, ts, source, author, thread, parent, paras, ptr},
        from, upto})),
      U32.from_nat(List.length(&2, P.Para,
        S.Shard.item.paras(S.Item{R.Record{id, ts, source, author, thread, parent, paras, ptr}, from, upto}))),
      0))
    : List<&2, Cl.Stat>}

# LAW: a shard adds one shard to each source it holds
law sources_one:
  for +src: String
  for +rest: List<&2, String>
  for +sts: List<&2, Cl.Stat>
  {Cl.Cli.stat.sources(src <> rest, sts) == Cl.Cli.stat.sources(rest, Cl.Cli.stat.put(sts, src, 0, 0, 1))
    : List<&2, Cl.Stat>}

# LAW: a shard adds its items, then one shard to each of its sources
law shards_one:
  for +n: U32
  for +items: List<&2, S.Item>
  for +sources: List<&2, String>
  for +chars: U32
  for +frozen: Bool
  for +rest: List<&2, S.Shard>
  for +sts: List<&2, Cl.Stat>
  {Cl.Cli.stat.shards(S.Shard{n, items, sources, chars, frozen} <> rest, sts)
    == Cl.Cli.stat.shards(rest, Cl.Cli.stat.sources(sources, Cl.Cli.stat.items(items, sts)))
    : List<&2, Cl.Stat>}

# LAW: a shard that was read is counted by its items
law light_read:
  for +shard: S.Shard
  for recs: U32
  for +sts: List<&2, Cl.Stat>
  {Cl.Cli.stat.light(None{}, shard, recs, sts) == Cl.Cli.stat.shards([shard], sts) : List<&2, Cl.Stat>}

# LAW: a shard that was not read adds, to its source, its source's records
# and the paragraphs its size file holds, and one shard
law light_sized:
  for +paras: Nat
  for +n: U32
  for +items: List<&2, S.Item>
  for +src: String
  for +more: List<&2, String>
  for +chars: U32
  for +frozen: Bool
  for +recs: U32
  for +sts: List<&2, Cl.Stat>
  {Cl.Cli.stat.light(Some{paras}, S.Shard{n, items, src <> more, chars, frozen}, recs, sts)
    == Cl.Cli.stat.put(sts, src, recs, U32.from_nat(paras), 1) : List<&2, Cl.Stat>}

# LAW: each source is one line of its counts
law lines_one:
  for +source: String
  for +records: U32
  for +paras: U32
  for +shards: U32
  for +rest: List<&2, Cl.Stat>
  {Cl.Cli.stat.lines(Cl.Stat{source, records, paras, shards} <> rest)
    == String.concat([source, " ", U32.show(records), " ", U32.show(paras), " ", U32.show(shards), "\n",
      Cl.Cli.stat.lines(rest)])
    : String}
