# proofs of laws/ShowFindsRecordAndParagraphs.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/cli.bend as Cl
import ../laws/ShowFindsRecordAndParagraphs.bend as Laws

def Laws.find_hit(id, rid, ts, source, author, thread, parent, paras, ptr, rest, h):
  %Equal.sym(Bool, String.eq(id, rid), True{}, h)
    : {Cl.Cli.find.if(_, R.Record{rid, ts, source, author, thread, parent, paras, ptr},
        Cl.Cli.find(id, rest))
      == Some{R.Record{rid, ts, source, author, thread, parent, paras, ptr}} : Maybe<&2, R.Record>}
  {==}

def Laws.find_miss(id, rid, ts, source, author, thread, parent, paras, ptr, rest, h):
  %Equal.sym(Bool, String.eq(id, rid), False{}, h)
    : {Cl.Cli.find.if(_, R.Record{rid, ts, source, author, thread, parent, paras, ptr},
        Cl.Cli.find(id, rest))
      == Cl.Cli.find(id, rest) : Maybe<&2, R.Record>}
  {==}

def Laws.find_none(_id):
  {==}

def Laws.picked_all(_ps):
  {==}

def Laws.picked_num(_n, _ps):
  {==}

def Laws.numbered_hit(num, k, start, end, text, rest, h):
  %Equal.sym(Bool, U32.is_eq(k, num), True{}, h)
    : {Cl.Cli.numbered.if(_, P.Para{k, start, end, text}, Cl.Cli.numbered(num, rest))
      == P.Para{k, start, end, text} <> Cl.Cli.numbered(num, rest) : List<&2, P.Para>}
  {==}

def Laws.numbered_miss(num, k, start, end, text, rest, h):
  %Equal.sym(Bool, U32.is_eq(k, num), False{}, h)
    : {Cl.Cli.numbered.if(_, P.Para{k, start, end, text}, Cl.Cli.numbered(num, rest))
      == Cl.Cli.numbered(num, rest) : List<&2, P.Para>}
  {==}

def Laws.numbered_none(_num):
  {==}
