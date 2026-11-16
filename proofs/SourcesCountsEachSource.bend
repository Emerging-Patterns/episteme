# proofs of laws/SourcesCountsEachSource.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/cli.bend as Cl
import ../laws/SourcesCountsEachSource.bend as Laws

def Laws.first_opens(_start, _end, _text, _rest):
  {==}

def Laws.first_later(k, _start, _end, _text, _rest, h):
  %Equal.sym(Bool, U32.is_eq(k, 1), False{}, h)
    : {Cl.Cli.first.if(_) == 0 : U32}
  {==}

def Laws.first_none(_u):
  {==}

def Laws.put_new(_src, _recs, _ps, _shs):
  {==}

def Laws.put_same(src, source, records, paras, shards, rest, recs, ps, shs, h):
  %Equal.sym(Cmp, String.order(src, source), EQ{}, h)
    : {Cl.Cli.stat.at(_, Cl.Stat{source, records, paras, shards}, rest, src, recs, ps, shs,
        _u => Cl.Cli.stat.put(rest, src, recs, ps, shs))
      == Cl.Stat{source, U32.add(records, recs), U32.add(paras, ps), U32.add(shards, shs)} <> rest
      : List<&2, Cl.Stat>}
  {==}

def Laws.put_before(src, source, records, paras, shards, rest, recs, ps, shs, h):
  %Equal.sym(Cmp, String.order(src, source), LT{}, h)
    : {Cl.Cli.stat.at(_, Cl.Stat{source, records, paras, shards}, rest, src, recs, ps, shs,
        _u => Cl.Cli.stat.put(rest, src, recs, ps, shs))
      == Cl.Stat{src, recs, ps, shs} <> Cl.Stat{source, records, paras, shards} <> rest
      : List<&2, Cl.Stat>}
  {==}

def Laws.put_after(src, source, records, paras, shards, rest, recs, ps, shs, h):
  %Equal.sym(Cmp, String.order(src, source), GT{}, h)
    : {Cl.Cli.stat.at(_, Cl.Stat{source, records, paras, shards}, rest, src, recs, ps, shs,
        _u => Cl.Cli.stat.put(rest, src, recs, ps, shs))
      == Cl.Stat{source, records, paras, shards} <> Cl.Cli.stat.put(rest, src, recs, ps, shs)
      : List<&2, Cl.Stat>}
  {==}

def Laws.items_one(_id, _ts, _source, _author, _thread, _parent, _paras, _ptr, _from, _upto, _rest, _sts):
  {==}

def Laws.sources_one(_src, _rest, _sts):
  {==}

def Laws.shards_one(_n, _items, _sources, _chars, _frozen, _rest, _sts):
  {==}

def Laws.light_read(_shard, _recs, _sts):
  {==}

def Laws.light_sized(_paras, _n, _items, _src, _more, _chars, _frozen, _recs, _sts):
  {==}

def Laws.lines_one(_source, _records, _paras, _shards, _rest):
  {==}
