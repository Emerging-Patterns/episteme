# `episteme show <id>[#<n>]` prints the first record of the log whose id is
# `id` (`Cli.find`, in log order: a record seen first wins over a later one
# with the same id, and no record is None), and of it the paragraphs
# `Cli.picked` names: every paragraph when no number was wanted, else those
# numbered `n` (`Cli.numbered`, in order, none when it has no such
# paragraph).
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/cli.bend as Cl

# LAW: the log's first record with the id is the one found
law find_hit:
  for +id: String
  for +rid: String
  for +ts: String
  for +source: String
  for +author: String
  for +thread: String
  for +parent: String
  for +paras: List<&2, P.Para>
  for +ptr: String
  for rest: List<&2, R.Record>
  for h: {String.eq(id, rid) == True{} : Bool}
  {Cl.Cli.find(id, R.Record{rid, ts, source, author, thread, parent, paras, ptr} <> rest)
    == Some{R.Record{rid, ts, source, author, thread, parent, paras, ptr}} : Maybe<&2, R.Record>}

# LAW: a record with another id is passed over
law find_miss:
  for +id: String
  for rid: String
  for ts: String
  for source: String
  for author: String
  for thread: String
  for parent: String
  for paras: List<&2, P.Para>
  for ptr: String
  for +rest: List<&2, R.Record>
  for h: {String.eq(id, rid) == False{} : Bool}
  {Cl.Cli.find(id, R.Record{rid, ts, source, author, thread, parent, paras, ptr} <> rest)
    == Cl.Cli.find(id, rest) : Maybe<&2, R.Record>}

# LAW: an empty log has no record
law find_none:
  for id: String
  {Cl.Cli.find(id, []) == None{} : Maybe<&2, R.Record>}

# LAW: with no number wanted, every paragraph is shown
law picked_all:
  for +ps: List<&2, P.Para>
  {Cl.Cli.picked(None{}, ps) == ps : List<&2, P.Para>}

# LAW: with a number wanted, the paragraphs numbered so are shown
law picked_num:
  for +n: U32
  for +ps: List<&2, P.Para>
  {Cl.Cli.picked(Some{n}, ps) == Cl.Cli.numbered(n, ps) : List<&2, P.Para>}

# LAW: a paragraph with the wanted number is kept, ahead of the rest's
law numbered_hit:
  for +num: U32
  for +k: U32
  for +start: U32
  for +end: U32
  for +text: String
  for +rest: List<&2, P.Para>
  for h: {U32.is_eq(k, num) == True{} : Bool}
  {Cl.Cli.numbered(num, P.Para{k, start, end, text} <> rest)
    == P.Para{k, start, end, text} <> Cl.Cli.numbered(num, rest) : List<&2, P.Para>}

# LAW: a paragraph with another number is dropped
law numbered_miss:
  for +num: U32
  for +k: U32
  for start: U32
  for end: U32
  for text: String
  for +rest: List<&2, P.Para>
  for h: {U32.is_eq(k, num) == False{} : Bool}
  {Cl.Cli.numbered(num, P.Para{k, start, end, text} <> rest)
    == Cl.Cli.numbered(num, rest) : List<&2, P.Para>}

# LAW: no paragraphs have none numbered
law numbered_none:
  for num: U32
  {Cl.Cli.numbered(num, []) == [] : List<&2, P.Para>}
