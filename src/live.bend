# episteme/src/live: which version of a record is current. The log is
# append-only, so a record is changed by appending a later record with the
# same id, and removed by appending a removal: a record with its id whose
# pointer is "removed". The current records of a list are the last record of
# each id, unless that one is a removal; a source's shards hold its current
# records, a changed one where its earlier version was (`Live.next`), and
# `show` finds the current record of an id. A batch that
# changes a record holds a removal of its id ahead of the new version, so a
# batch of a source that changes or removes a record holds a removal. Pure:
# no IO.
import Base
import ./record.bend as R
import ./shard.bend as S

# a record's id
def Live.id(rec: R.Record) -> String:
  match rec:
    case R.Record{id, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
      id

# a record's pointer
def Live.ptr(rec: R.Record) -> String:
  match rec:
    case R.Record{_id, _ts, _source, _author, _thread, _parent, _paras, ptr}:
      ptr

# the pointer of a removal
def Live.removed() -> String:
  "removed"

# True when a record is a removal: its pointer is "removed"
def Live.gone(+rec: R.Record) -> Bool:
  String.eq(Live.ptr(rec), Live.removed())

# True when some record of xs is a removal: its source's shards are then
# packed again from its current records, never extended
def Live.marked(xs: List<&2, R.Record>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      Bool.or(Live.gone(x), Live.marked(rest))

# True when id is the id of some record of xs
def Live.has(+id: String, xs: List<&2, R.Record>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      Bool.or(String.eq(Live.id(x), id), Live.has(id, rest))

# x ahead of rest unless a later record has its id or it is a removal
def Live.put(later: Bool, gone: Bool, rec: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match later:
    case True{}:
      rest
    case False{}:
      match gone:
        case True{}:
          rest
        case False{}:
          rec <> rest

# the current records of xs, in order: each record of xs that no later
# record of xs has the id of, unless it is a removal
def Live.of(xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match xs:
    case Nil{}:
      []
    case Con{+x, +rest}:
      Live.put(Live.has(Live.id(x), rest), Live.gone(x), x, Live.of(rest))

# what a record with the id gives: the find in the rest when a later record
# has the id, none when it is a removal, else the record
def Live.found(
  later: Bool,
  gone: Bool,
  rec: R.Record,
  next: Maybe<&2, R.Record>
) -> Maybe<&2, R.Record>:
  match later:
    case True{}:
      next
    case False{}:
      match gone:
        case True{}:
          None{}
        case False{}:
          Some{rec}

# what the find at x gives: when x has the id, what Live.found says, the
# later records' ids checked only then; else the find in the rest
def Live.found.at(
  hit: Bool,
  later: Unit -> Bool,
  gone: Bool,
  rec: R.Record,
  next: Maybe<&2, R.Record>
) -> Maybe<&2, R.Record>:
  match hit:
    case True{}:
      Live.found(later(Unit{}), gone, rec, next)
    case False{}:
      next

# the current record of xs with the id, or none when there is none or the
# last record with it is a removal: what `show` prints, in one pass over
# the log, where Live.of would be quadratic
def Live.find(+id: String, xs: List<&2, R.Record>) -> Maybe<&2, R.Record>:
  match xs:
    case Nil{}:
      None{}
    case Con{+x, +rest}:
      Live.found.at(String.eq(Live.id(x), id), _u => Live.has(Live.id(x), rest),
        Live.gone(x), x, Live.find(id, rest))

# --- reading a source's records back from its shards ---

# True when a line's record id is the one the line before was of
def Live.same(last: Maybe<&2, String>, +id: String) -> Bool:
  match last:
    case None{}:
      False{}
    case Some{prev}:
      String.eq(id, prev)

# the record of a line ahead of the rest unless the line before was of it
def Live.firsts.if(same: Bool, rec: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match same:
    case True{}:
      rest
    case False{}:
      rec <> rest

# the records of lines, in order, each once at the first of its run of
# lines; last is the id of the line before them
def Live.firsts(ls: List<&2, S.Shard.Line()>, last: Maybe<&2, String>) -> List<&2, R.Record>:
  match ls:
    case Nil{}:
      []
    case Con{line, rest}:
      match line:
        case (+rec, _pa):
          Live.firsts.if(Live.same(last, Live.id(rec)), rec,
            Live.firsts(rest, Some{Live.id(rec)}))

# the paragraphs of shards, in order, each beside its record
def Live.lines(ss: List<&2, S.Shard>) -> List<&2, S.Shard.Line()>:
  match ss:
    case Nil{}:
      []
    case Con{sh, rest}:
      match sh:
        case S.Shard{_n, items, _sources, _chars, _frozen}:
          List.append(&2, S.Shard.Line(), S.Shard.lines(items), Live.lines(rest))

# the records a source's shards hold, in order, each once
def Live.held(ss: List<&2, S.Shard>) -> List<&2, R.Record>:
  Live.firsts(Live.lines(ss), None{})

# --- a batch applied to a source's current records ---

# what a current record becomes after a batch, ahead of rest: itself when
# the batch names no record with its id, else the batch's last version of
# the id, nothing when that is a removal
def Live.kept.one(
  named: Bool,
  rec: R.Record,
  last: Maybe<&2, R.Record>,
  rest: List<&2, R.Record>
) -> List<&2, R.Record>:
  match named:
    case False{}:
      rec <> rest
    case True{}:
      match last:
        case None{}:
          rest
        case Some{y}:
          y <> rest

# the records m after the batch ys, each at its place: a record whose id ys
# names in its last version, or gone when that is a removal, every other as
# it was
def Live.kept(m: List<&2, R.Record>, +ys: List<&2, R.Record>) -> List<&2, R.Record>:
  match m:
    case Nil{}:
      []
    case Con{+r, rest}:
      Live.kept.one(Live.has(Live.id(r), ys), r, Live.find(Live.id(r), ys), Live.kept(rest, ys))

# rec ahead of rest unless it has the id
def Live.less.if(hit: Bool, rec: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match hit:
    case True{}:
      rest
    case False{}:
      rec <> rest

# the records of zs whose id is not id, in order
def Live.less(+id: String, zs: List<&2, R.Record>) -> List<&2, R.Record>:
  match zs:
    case Nil{}:
      []
    case Con{+z, rest}:
      Live.less.if(String.eq(Live.id(z), id), z, Live.less(id, rest))

# the records of zs whose id no record of m has, in order
def Live.added(m: List<&2, R.Record>, zs: List<&2, R.Record>) -> List<&2, R.Record>:
  match m:
    case Nil{}:
      zs
    case Con{r, rest}:
      Live.added(rest, Live.less(Live.id(r), zs))

# a source's current records m after the batch ys: m with each record at
# its place in the last version ys gives its id, less those ys removes, then
# the current records of ys whose ids m lacks
def Live.next(+m: List<&2, R.Record>, +ys: List<&2, R.Record>) -> List<&2, R.Record>:
  List.append(&2, R.Record, Live.kept(m, ys), Live.added(m, Live.of(ys)))

# a source's shards packed again, from shard 1, from the records they hold
# after the batch ys
def Live.repack(+cap: U32, ss: List<&2, S.Shard>, +ys: List<&2, R.Record>) -> List<&2, S.Shard>:
  S.Shard.pack(cap, 1, Live.next(Live.held(ss), ys))
# --- the source an id names ---

# what the text from chr on gives: the text before its last "@" when the
# rest has one, "" when chr is the last "@", else none
def Live.cut.if(at: Bool, chr: Char, got: Maybe<&2, String>) -> Maybe<&2, String>:
  match got:
    case Some{before}:
      Some{SCon{chr, before}}
    case None{}:
      Bool.pick(Maybe<&2, String>, at, Some{""}, None{})

# the text before the last "@" of str, or none when it has no "@": the
# source a record id names when the id is <source>@<key> with no "@" in
# the key
def Live.source(str: String) -> Maybe<&2, String>:
  match str:
    case SNil{}:
      None{}
    case SCon{+chr, rest}:
      Live.cut.if(Char.is_eq(chr, '@'), chr, Live.source(rest))

# rec when it has the id, else the first of the rest with it
def Live.pick.if(hit: Bool, rec: R.Record, rest: Maybe<&2, R.Record>) -> Maybe<&2, R.Record>:
  match hit:
    case True{}:
      Some{rec}
    case False{}:
      rest

# the first record of xs with the id, or none: what `show` takes from the
# records a source's shards hold
def Live.pick(+id: String, xs: List<&2, R.Record>) -> Maybe<&2, R.Record>:
  match xs:
    case Nil{}:
      None{}
    case Con{+x, rest}:
      Live.pick.if(String.eq(Live.id(x), id), x, Live.pick(id, rest))
