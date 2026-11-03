# the definitions the laws are stated in: paragraphs, items, excerpts, order
# and time
import Base
import ../../src/para.bend as P
import ../../src/record.bend as R
import ../../src/shard.bend as S
import ../../src/filter.bend as F
import ../../src/excerpt.bend as E

# --- the specification's own words ---

# a paragraph's number
def para.n(pa: P.Para) -> U32:
  match pa:
    case P.Para{n, _start, _end, _text}:
      n

# where a paragraph starts in the text
def para.start(pa: P.Para) -> U32:
  match pa:
    case P.Para{_n, start, _end, _text}:
      start

# where a paragraph ends in the text, exclusive
def para.end(pa: P.Para) -> U32:
  match pa:
    case P.Para{_n, _start, end, _text}:
      end

# a paragraph's text
def para.text(pa: P.Para) -> String:
  match pa:
    case P.Para{_n, _start, _end, text}:
      text

# the code points of text from offset lo up to offset hi, exclusive
def slice(text: String, +lo: Nat, hi: Nat) -> String:
  String.take(String.drop(text, lo), Nat.sub(hi, lo))

# True when every code point of str is whitespace (an empty str is)
def blank(str: String) -> Bool:
  match str:
    case SNil{}:
      True{}
    case SCon{h, t}:
      Bool.and(Char.is_space(h), blank(t))

# pa is one of ps
def In(pa: P.Para, ps: List<&2, P.Para>) -> Type:
  match ps:
    case Nil{}:
      Empty
    case Con{head, tail}:
      Or({pa == head : P.Para}, In(pa, tail))

# the numbers of ps, in order
def numbers(ps: List<&2, P.Para>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      []
    case Con{h, t}:
      para.n(h) <> numbers(t)

# count numbers counting up from num
def upto(count: Nat, +num: U32) -> List<&2, U32>:
  match count:
    case 0n:
      []
    case 1n+rest:
      num <> upto(rest, U32.inc(num))

# --- where paragraphs end and what they cover ---

# True for the line feed
def nl(chr: Char) -> Bool:
  U32.is_eq(Char.to_u32(chr), 10)

# True when no code point of str is a line feed
def nonl(str: String) -> Bool:
  match str:
    case SNil{}:
      True{}
    case SCon{head, tail}:
      Bool.and(Bool.not(nl(head)), nonl(tail))

# the first line from head on: empty when head is a line feed, else head
# and then the first line of the rest
def line.if(feed: Bool, head: Char, rest: Unit -> String) -> String:
  match feed:
    case True{}:
      SNil{}
    case False{}:
      SCon{head, rest(Unit{})}

# the first line of str: its code points up to the first line feed
def line(str: String) -> String:
  match str:
    case SNil{}:
      SNil{}
    case SCon{+head, tail}:
      line.if(nl(head), head, _u => line(tail))

# the text after a paragraph
def after(text: String, pa: P.Para) -> String:
  String.drop(text, U32.to_nat(para.end(pa)))

# the paragraph is cut at a line feed: with the line after it, it would be
# longer than Para.max()
def cut_feed(text: String, pa: P.Para) -> Type:
  Exists(Char, head => Exists(String, rest =>
    Pair({after(text, pa) == SCon{head, rest} : String},
    Pair({nl(head) == True{} : Bool},
      {Nat.is_lt(U32.to_nat(P.Para.max()),
        Nat.add(String.length(para.text(pa)), 1n+String.length(line(rest))))
        == True{} : Bool}))))

# the paragraph is cut hard: Para.max() code points with no line feed
def cut_hard(pa: P.Para) -> Type:
  Pair({String.length(para.text(pa)) == U32.to_nat(P.Para.max()) : Nat},
    {nonl(para.text(pa)) == True{} : Bool})

# a record's id
def rec.id(record: R.Record) -> String:
  match record:
    case R.Record{id, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
      id

# a record's source
def rec.source(record: R.Record) -> String:
  match record:
    case R.Record{_id, _ts, source, _author, _thread, _parent, _paras, _ptr}:
      source

# a record's paragraphs
def rec.paras(record: R.Record) -> List<&2, P.Para>:
  match record:
    case R.Record{_id, _ts, _source, _author, _thread, _parent, paras, _ptr}:
      paras

# how many paragraphs a record has
def rec.count(record: R.Record) -> Nat:
  List.length(&2, P.Para, rec.paras(record))

# the length of a record's header line
def rec.head(record: R.Record) -> Nat:
  String.length(R.Record.header(record))

# the code points of the texts of ps
def texts(ps: List<&2, P.Para>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{head, tail}:
      Nat.add(String.length(para.text(head)), texts(tail))

# an item's record
def item.rec(it: S.Item) -> R.Record:
  match it:
    case S.Item{rec, _from, _upto}:
      rec

# the paragraphs an item holds: those at positions from to upto of its
# record, counting from 1
def item.paras(it: S.Item) -> List<&2, P.Para>:
  match it:
    case S.Item{rec, +from, upto}:
      List.take(&2, P.Para,
        List.drop(&2, P.Para, rec.paras(rec), Nat.sub(U32.to_nat(from), 1n)),
        Nat.sub(1n+U32.to_nat(upto), U32.to_nat(from)))

# an item's size: its record's header line and its paragraph texts
def item.size(+it: S.Item) -> Nat:
  Nat.add(rec.head(item.rec(it)), texts(item.paras(it)))

# the size of items: the sum of theirs
def size(its: List<&2, S.Item>) -> Nat:
  match its:
    case Nil{}:
      0n
    case Con{head, tail}:
      Nat.add(item.size(head), size(tail))

# a shard's items
def shard.items(sh: S.Shard) -> List<&2, S.Item>:
  match sh:
    case S.Shard{_n, items, _sources, _chars, _frozen}:
      items

# each of ps beside the record it is of
def pairs(+record: R.Record, ps: List<&2, P.Para>) -> List<&2, S.Shard.Line()>:
  match ps:
    case Nil{}:
      []
    case Con{head, tail}:
      (record, head) <> pairs(record, tail)

# the paragraphs of records, in order, each beside its record
def cover(xs: List<&2, R.Record>) -> List<&2, S.Shard.Line()>:
  match xs:
    case Nil{}:
      []
    case Con{+r, tail}:
      List.append(&2, S.Shard.Line(), pairs(r, rec.paras(r)), cover(tail))

# the paragraphs items hold, in order, each beside its record
def items.cover(its: List<&2, S.Item>) -> List<&2, S.Shard.Line()>:
  match its:
    case Nil{}:
      []
    case Con{+it, tail}:
      List.append(&2, S.Shard.Line(), pairs(item.rec(it), item.paras(it)),
        items.cover(tail))

# every record of xs has fewer than 2^32 paragraphs: its count survives a
# round trip through U32
def counted(xs: List<&2, R.Record>) -> Type:
  match xs:
    case Nil{}:
      Unit
    case Con{+r, tail}:
      Pair({U32.to_nat(U32.from_nat(rec.count(r))) == rec.count(r) : Nat},
        counted(tail))

# True when each of xs is below the one after it, prev below the first
def ascending.from(xs: List<&2, String>, +prev: String) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+head, tail}:
      Bool.and(String.is_lt(prev, head), ascending.from(tail, head))

# True when each of xs is below the one after it: sorted, no two equal
def ascending(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+head, tail}:
      ascending.from(tail, head)

# True when text is one of xs
def mem(+text: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{head, tail}:
      Bool.or(String.eq(text, head), mem(text, tail))

# True when text is the source of one of its
def has(+text: String, its: List<&2, S.Item>) -> Bool:
  match its:
    case Nil{}:
      False{}
    case Con{head, tail}:
      Bool.or(String.eq(text, rec.source(item.rec(head))), has(text, tail))

# True when sel would select every Claude chat: exact chat:claude, or the
# prefix chat:, chat:claude/ or the empty prefix
def chat_wide(sel: F.Sel) -> Bool:
  match sel:
    case F.Exact{text}:
      String.eq(text, "chat:claude")
    case F.Prefix{+text}:
      Bool.or(String.eq(text, "chat:"),
        Bool.or(String.eq(text, "chat:claude/"), String.eq(text, "")))

# True when some selector of sels is chat-wide
def some_wide(sels: List<&2, F.Sel>) -> Bool:
  match sels:
    case Nil{}:
      False{}
    case Con{sel, rest}:
      Bool.or(chat_wide(sel), some_wide(rest))

# True when the check must refuse sels: sels is empty or holds a chat-wide
# selector
def refused(sels: List<&2, F.Sel>) -> Bool:
  match sels:
    case Nil{}:
      True{}
    case Con{sel, rest}:
      some_wide(sel <> rest)

# a record's timestamp
def rec.ts(record: R.Record) -> String:
  match record:
    case R.Record{_id, ts, _source, _author, _thread, _parent, _paras, _ptr}:
      ts

# an excerpt's record
def ex.rec(cur: E.Ex) -> R.Record:
  match cur:
    case E.Ex{rec, _paras}:
      rec

# an excerpt's paragraphs
def ex.paras(cur: E.Ex) -> List<&2, P.Para>:
  match cur:
    case E.Ex{_rec, paras}:
      paras

# the paragraphs of excerpts, in order, each beside its excerpt's record
def lines(xs: List<&2, E.Ex>) -> List<&2, S.Shard.Line()>:
  match xs:
    case Nil{}:
      []
    case Con{+x, tail}:
      List.append(&2, S.Shard.Line(), pairs(ex.rec(x), ex.paras(x)),
        lines(tail))

# line ahead of rest when the reader named its label
def named.if(
  hit: Bool,
  line: S.Shard.Line(),
  rest: List<&2, S.Shard.Line()>
) -> List<&2, S.Shard.Line()>:
  match hit:
    case True{}:
      line <> rest
    case False{}:
      rest

# the lines ps, labelled p<idx>, p<idx+1>, ..., whose labels are among ls
def named(
  ps: List<&2, S.Shard.Line()>,
  +idx: U32,
  +ls: List<&2, String>
) -> List<&2, S.Shard.Line()>:
  match ps:
    case Nil{}:
      []
    case Con{line, tail}:
      named.if(mem(String.append("p", U32.show(idx)), ls), line,
        named(tail, U32.inc(idx), ls))

# True when ps holds a paragraph
def full(ps: List<&2, P.Para>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{_head, _tail}:
      True{}

# the records of xs, in order
def recs(xs: List<&2, E.Ex>) -> List<&2, R.Record>:
  match xs:
    case Nil{}:
      []
    case Con{x, tail}:
      ex.rec(x) <> recs(tail)

# the label number after ps, labelled from p<idx> on
def skip(ps: List<&2, P.Para>, idx: U32) -> U32:
  match ps:
    case Nil{}:
      idx
    case Con{_head, tail}:
      skip(tail, U32.inc(idx))

# True when text is the label of one of labels
def labelled(+text: String, labels: List<&2, S.Shard.Label()>) -> Bool:
  match labels:
    case Nil{}:
      False{}
    case Con{lab, tail}:
      match lab:
        case (l, _at):
          Bool.or(String.eq(text, l), labelled(text, tail))

# an excerpt's timestamp
def ex.ts(cur: E.Ex) -> String:
  rec.ts(ex.rec(cur))

# the excerpts of xs whose timestamp is time, in order
def only(+time: String, xs: List<&2, E.Ex>) -> List<&2, E.Ex>:
  match xs:
    case Nil{}:
      []
    case Con{+x, tail}:
      List.filter.put(E.Ex, x, only(time, tail), String.eq(ex.ts(x), time))

# True when some paragraph of ps has the number num
def numbered(+num: U32, ps: List<&2, P.Para>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{p, tail}:
      Bool.or(U32.is_eq(para.n(p), num), numbered(num, tail))

# True when some excerpt of xs has the record id id and a paragraph
# numbered num
def holds(+id: String, +num: U32, xs: List<&2, E.Ex>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, tail}:
      Bool.or(Bool.and(String.eq(rec.id(ex.rec(x)), id),
        numbered(num, ex.paras(x))), holds(id, num, tail))

# a record of one or more paragraphs at time ts
def at(id: String, ts: String, ps: List<&2, P.Para>) -> R.Record:
  R.Record{id, ts, "book:x/y", "", "", "", ps, ""}

# a book excerpt of one paragraph at offsets 100 to 200 of its file
def page(source: String) -> List<&2, E.Ex>:
  [E.Ex{R.Record{"b1", "t", source, "", "", "", [P.Para{7, 100, 200, "p"}],
    ""}, [P.Para{7, 100, 200, "p"}]}]

# the last of ss, or dflt when there is none
def final(ss: List<&2, S.Shard>, dflt: S.Shard) -> S.Shard:
  match ss:
    case Nil{}:
      dflt
    case Con{head, tail}:
      final(tail, head)

# True when a record of time ts is at or after since: ts is not before it
def at_or_after(+ts: String, +since: String) -> Bool:
  Bool.not(String.is_lt(ts, since))
