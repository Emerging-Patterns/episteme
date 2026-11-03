# episteme/src/shard: records packed into numbered shards, the unit one
# reader reads whole. Every shard but the last is frozen and never changes;
# the last is the tail. Pure: no IO.
import Base
import ./para.bend as P
import ./record.bend as R
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# the paragraphs at positions from to upto (counting from 1, inclusive) of
# a record
type Item is Data:
  Item{rec: R.Record, from: U32, upto: U32}

# a shard: its number, its items in order, the sorted distinct sources of
# their records, its size in code points (each item's header line and
# paragraph texts), and whether it is frozen
type Shard is Data:
  Shard{n: U32, items: List<&2, Item>, sources: List<&2, String>, chars: U32,
    frozen: Bool}

# the shard being filled: its items, in order, and its size
type Open is Data:
  Open{items: List<&2, Item>, size: Nat}

# what one record gives: the shards it freezes, in order, and the open one
# after it
type Step is Data:
  Step{out: List<&2, Open>, next: Open}

# a paragraph beside its record
def Shard.Line() -> Data:
  Sigma<&2, &2, R.Record, _r => P.Para>

# a label beside the record id and paragraph number it stands for
def Shard.Label() -> Data:
  Sigma<&2, &2, String, _l => Sigma<&2, &2, String, _i => U32>>

# a record's paragraphs
def Shard.paras(rec: R.Record) -> List<&2, P.Para>:
  match rec:
    case R.Record{_id, _ts, _source, _author, _thread, _parent, paras, _ptr}:
      paras

# a whole record as one item
def Shard.whole(+rec: R.Record) -> Item:
  Item{rec, 1, U32.from_nat(List.length(&2, P.Para, Shard.paras(rec)))}

# the item of rec's paragraphs from done + 1 to done + 1 + extra
def Shard.piece(rec: R.Record, +done: Nat, extra: Nat) -> Item:
  Item{rec, U32.from_nat(1n+done), U32.from_nat(1n+Nat.add(done, extra))}

# the open shard frozen ahead of what st freezes
def Shard.emit(open: Open, st: Step) -> Step:
  match st:
    case Step{out, next}:
      Step{open <> out, next}

# the shards out frozen ahead of what st freezes
def Shard.after(out: List<&2, Open>, st: Step) -> Step:
  match st:
    case Step{more, next}:
      Step{List.append(&2, Open, out, more), next}

# a non-empty open shard, frozen
def Shard.shut(cur: List<&2, Item>, size: Nat) -> List<&2, Open>:
  match cur:
    case Nil{}:
      []
    case Con{head, tail}:
      [Open{head <> tail, size}]

# where the next piece starts: after the piece being built, unless the
# next paragraph joins it
def Shard.cut.j(fits: Bool, +done: Nat, extra: Nat) -> Nat:
  match fits:
    case True{}:
      done
    case False{}:
      Nat.add(done, 1n+extra)

# how many paragraphs, less one, the next piece holds so far
def Shard.cut.m(fits: Bool, extra: Nat) -> Nat:
  match fits:
    case True{}:
      1n+extra
    case False{}:
      0n

# how many code points of text the next piece holds so far
def Shard.cut.sz(fits: Bool, sz: Nat, plen: Nat) -> Nat:
  match fits:
    case True{}:
      Nat.add(sz, plen)
    case False{}:
      plen

# what the rest gives, after the piece being built when the next paragraph
# did not join it
def Shard.cut.if(
  fits: Bool,
  rec: R.Record,
  hlen: Nat,
  done: Nat,
  extra: Nat,
  sz: Nat,
  st: Step
) -> Step:
  match fits:
    case True{}:
      st
    case False{}:
      Shard.emit(Open{[Shard.piece(rec, done, extra)], Nat.add(hlen, sz)}, st)

# rec's paragraphs ps after the piece being built, which holds its
# paragraphs from done + 1 to done + 1 + extra and sz code points of their
# text; hlen is the length of rec's header line. A paragraph joins the piece while the
# piece still fits in cap; else the piece fills a shard of its own
def Shard.cut(
  ps: List<&2, P.Para>,
  +cap: Nat,
  +rec: R.Record,
  +hlen: Nat,
  +done: Nat,
  +extra: Nat,
  +sz: Nat
) -> Step:
  match ps:
    case Nil{}:
      Step{[], Open{[Shard.piece(rec, done, extra)], Nat.add(hlen, sz)}}
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          +l = String.length(text)
          +fits = Nat.is_le(Nat.add(hlen, Nat.add(sz, l)), cap)
          Shard.cut.if(fits, rec, hlen, done, extra, sz,
            Shard.cut(rest, cap, rec, hlen, Shard.cut.j(fits, done, extra),
              Shard.cut.m(fits, extra), Shard.cut.sz(fits, sz, l)))

# a record larger than cap, cut at paragraph boundaries into items that
# each fill a shard; the last item stays open
def Shard.split(ps: List<&2, P.Para>, +cap: Nat, +rec: R.Record, rsize: Nat) -> Step:
  match ps:
    case Nil{}:
      Step{[], Open{[Shard.whole(rec)], rsize}}
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          Shard.cut(rest, cap, rec, String.length(R.Record.header(rec)), 0n,
            0n, String.length(text))

# a record of size rsize on an empty shard: whole when it fits, else cut
def Shard.lay.if(small: Bool, +cap: Nat, +rec: R.Record, rsize: Nat) -> Step:
  match small:
    case True{}:
      Step{[], Open{[Shard.whole(rec)], rsize}}
    case False{}:
      Shard.split(Shard.paras(rec), cap, rec, rsize)

# a record of size rsize at the end of the open shard: it joins when it fits;
# else the open shard freezes and the record starts the next one
def Shard.step.if(
  fits: Bool,
  +cap: Nat,
  cur: List<&2, Item>,
  size: Nat,
  +rec: R.Record,
  +rsize: Nat
) -> Step:
  match fits:
    case True{}:
      Step{[], Open{List.append(&2, Item, cur, [Shard.whole(rec)]),
        Nat.add(size, rsize)}}
    case False{}:
      Shard.after(Shard.shut(cur, size),
        Shard.lay.if(Nat.is_le(rsize, cap), cap, rec, rsize))

# one record at the end of the open shard
def Shard.step(+cap: Nat, st: Open, +rec: R.Record) -> Step:
  match st:
    case Open{cur, +size}:
      +c = R.Record.size(rec)
      Shard.step.if(Nat.is_le(Nat.add(size, c), cap), cap, cur, size, rec, c)

# the step's frozen shards, then what the rest gives from its open shard
def Shard.then(st: Step, rest: Open -> List<&2, Open>) -> List<&2, Open>:
  match st:
    case Step{out, next}:
      List.append(&2, Open, out, rest(next))

# the records xs packed after the open shard st: the frozen shards, then
# the open one last
def Shard.run(xs: List<&2, R.Record>, +cap: Nat, st: Open) -> List<&2, Open>:
  match xs:
    case Nil{}:
      [st]
    case Con{rec, rest}:
      Shard.then(Shard.step(cap, st, rec), next => Shard.run(rest, cap, next))

# src before top and the rest, the same as top, or after it, by order: then
# ins is the rest with src in its place
def Shard.insert.at(
  order: Cmp,
  src: String,
  top: String,
  rest: List<&2, String>,
  ins: List<&2, String>
) -> List<&2, String>:
  match order:
    case LT{}:
      src <> top <> rest
    case EQ{}:
      top <> rest
    case GT{}:
      top <> ins

# a source among the sorted distinct sources ys, at its place
def Shard.insert(ys: List<&2, String>, +src: String) -> List<&2, String>:
  match ys:
    case Nil{}:
      [src]
    case Con{+y, +rest}:
      Shard.insert.at(String.order(src, y), src, y, rest, Shard.insert(rest, src))

# an item's source
def Shard.source(it: Item) -> String:
  match it:
    case Item{rec, _from, _upto}:
      match rec:
        case R.Record{_id, _ts, source, _author, _thread, _parent, _paras, _ptr}:
          source

# the sorted distinct sources of items
def Shard.sources(its: List<&2, Item>) -> List<&2, String>:
  match its:
    case Nil{}:
      []
    case Con{it, rest}:
      Shard.insert(Shard.sources(rest), Shard.source(it))

# whether any shards follow
def Shard.more(gs: List<&2, Open>) -> Bool:
  match gs:
    case Nil{}:
      False{}
    case Con{_head, _tail}:
      True{}

# shard num of the open shard
def Shard.make(num: U32, open: Open, frozen: Bool) -> Shard:
  match open:
    case Open{+items, size}:
      Shard{num, items, Shard.sources(items), U32.from_nat(size), frozen}

# shards numbered from num; all but the last are frozen
def Shard.number(gs: List<&2, Open>, +num: U32) -> List<&2, Shard>:
  match gs:
    case Nil{}:
      []
    case Con{g, +rest}:
      Shard.make(num, g, Shard.more(rest)) <> Shard.number(rest, U32.inc(num))

# records packed into shards numbered from next_n: records join the open
# shard whole while they fit in cap; when the next does not, the open shard
# freezes, and a record larger than cap is cut at paragraph boundaries into
# items that each fill a shard. The last shard is the tail, never frozen
def Shard.pack(cap: U32, next_n: U32, tail: List<&2, R.Record>) -> List<&2, Shard>:
  Shard.number(Shard.run(tail, U32.to_nat(cap), Open{[], 0n}), next_n)

# the paragraphs an item holds
def Shard.item.paras(it: Item) -> List<&2, P.Para>:
  match it:
    case Item{rec, +from, upto}:
      List.take(&2, P.Para,
        List.drop(&2, P.Para, Shard.paras(rec), Nat.sub(U32.to_nat(from), 1n)),
        Nat.sub(1n+U32.to_nat(upto), U32.to_nat(from)))

# each of ps beside its record
def Shard.pairs(+rec: R.Record, ps: List<&2, P.Para>) -> List<&2, Shard.Line()>:
  match ps:
    case Nil{}:
      []
    case Con{pa, rest}:
      (rec, pa) <> Shard.pairs(rec, rest)

# the paragraphs items hold, in order, each beside its record
def Shard.lines(its: List<&2, Item>) -> List<&2, Shard.Line()>:
  match its:
    case Nil{}:
      []
    case Con{+it, rest}:
      match it:
        case Item{+rec, from, upto}:
          List.append(&2, Shard.Line(),
            Shard.pairs(rec, Shard.item.paras(Item{rec, from, upto})),
            Shard.lines(rest))

# the label p<idx>
def Shard.label(idx: U32) -> String:
  String.append("p", U32.show(idx))

# labels from p<idx> on for ps, each with its record id and paragraph number
def Shard.labels.go(ps: List<&2, Shard.Line()>, +idx: U32) -> List<&2, Shard.Label()>:
  match ps:
    case Nil{}:
      []
    case Con{line, rest}:
      match line:
        case (rec, pa):
          match rec pa:
            case R.Record{id, _ts, _source, _author, _thread, _parent, _paras, _ptr}
              P.Para{n, _start, _end, _text}:
              (Shard.label(idx), (id, n)) <> Shard.labels.go(rest, U32.inc(idx))

# a shard's labels p1, p2, ... in the order of its paragraphs, each with
# its record id and paragraph number
def Shard.labels(shard: Shard) -> List<&2, Shard.Label()>:
  match shard:
    case Shard{_n, items, _sources, _chars, _frozen}:
      Shard.labels.go(Shard.lines(items), 1)

# the paragraphs ps as lines "[p<k>] <text>", k counting from idx
def Shard.render.paras(ps: List<&2, P.Para>, +idx: U32) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          String.concat(["[", Shard.label(idx), "] ", text, "\n",
            Shard.render.paras(rest, U32.inc(idx))])

# a blank line when more items follow
def Shard.render.gap(its: List<&2, Item>) -> String:
  match its:
    case Nil{}:
      ""
    case Con{_head, _tail}:
      "\n"

# items, each its header line and then its paragraphs labelled from idx on,
# apart by a blank line
def Shard.render.items(its: List<&2, Item>, +idx: U32) -> String:
  match its:
    case Nil{}:
      ""
    case Con{it, +rest}:
      match it:
        case Item{+rec, from, upto}:
          +ps = Shard.item.paras(Item{rec, from, upto})
          String.concat([R.Record.header(rec), "\n", Shard.render.paras(ps, idx),
            Shard.render.gap(rest),
            Shard.render.items(rest,
              U32.add(idx, U32.from_nat(List.length(&2, P.Para, ps))))])

# a shard as its reader text: each item's header line, then one line
# "[p<k>] <text>" per paragraph, k counting from 1 across the shard, items
# apart by a blank line
def Shard.render(shard: Shard) -> String:
  match shard:
    case Shard{_n, items, _sources, _chars, _frozen}:
      Shard.render.items(items, 1)

# an item as the JSON object {"rec", "from", "upto"}, its record as the
# record's own JSON
def Shard.item.json(it: Item) -> Value.Json:
  match it:
    case Item{rec, from, upto}:
      Json.obj([("rec", R.Record.to_json(rec)), ("from", R.Record.u32(from)),
        ("upto", R.Record.u32(upto))])

# items as JSON objects, in order
def Shard.items.json(its: List<&2, Item>) -> List<&2, Value.Json>:
  match its:
    case Nil{}:
      []
    case Con{it, rest}:
      Shard.item.json(it) <> Shard.items.json(rest)

# texts as JSON strings, in order
def Shard.strs.json(xs: List<&2, String>) -> List<&2, Value.Json>:
  match xs:
    case Nil{}:
      []
    case Con{x, rest}:
      Json.str(x) <> Shard.strs.json(rest)

# a shard as a JSON object
def Shard.to_value(shard: Shard) -> Value.Json:
  match shard:
    case Shard{n, items, sources, chars, frozen}:
      Json.obj([("n", R.Record.u32(n)),
        ("items", Json.arr(Shard.items.json(items))),
        ("sources", Json.arr(Shard.strs.json(sources))),
        ("chars", R.Record.u32(chars)), ("frozen", Json.bool(frozen))])

# a shard as one compact JSON object, with no newline
def Shard.to_json(shard: Shard) -> String:
  Json.print(Shard.to_value(shard))

# True when 1 <= from <= upto <= the record's paragraph count
def Shard.item.ok(+from: U32, +upto: U32, rec: R.Record) -> Bool:
  Bool.and(U32.is_le(1, from), Bool.and(U32.is_le(from, upto),
    U32.is_le(upto, U32.from_nat(List.length(&2, P.Para, Shard.paras(rec))))))

# the item when ok, else None
def Shard.item.keep(ok: Bool, it: Item) -> Maybe<&2, Item>:
  match ok:
    case True{}:
      Some{it}
    case False{}:
      None{}

# the item of the parts read, or None when one is missing or its positions
# are not 1 <= from <= upto <= the record's paragraph count
def Shard.item.of.go(
  rec: Maybe<&2, R.Record>,
  from: Maybe<&2, U32>,
  upto: Maybe<&2, U32>
) -> Maybe<&2, Item>:
  match rec from upto:
    case Some{+rc} Some{+fr} Some{+up}:
      Shard.item.keep(Shard.item.ok(fr, up, rc), Item{rc, fr, up})
    case _ _ _:
      None{}

# an item read from its JSON object, or None when it is not one
def Shard.item.of(+js: Value.Json) -> Maybe<&2, Item>:
  Shard.item.of.go(R.Record.of_json(Json.get(js, "rec")),
    Json.as_u32(Json.get(js, "from")), Json.as_u32(Json.get(js, "upto")))

# src ahead of xs, or None when either is missing
def Shard.cons(
  -A: Data,
  src: Maybe<&2, A>,
  xs: Maybe<&2, List<&2, A>>
) -> Maybe<&2, List<&2, A>>:
  match src xs:
    case Some{y} Some{ys}:
      Some{y <> ys}
    case _ _:
      None{}

# items read from JSON objects, in order, or None when one is not an item
def Shard.items.of(js: List<&2, Value.Json>) -> Maybe<&2, List<&2, Item>>:
  match js:
    case Nil{}:
      Some{[]}
    case Con{head, rest}:
      Shard.cons(Item, Shard.item.of(head), Shard.items.of(rest))

# texts read from JSON strings, in order, or None when one is not a string
def Shard.strs.of(js: List<&2, Value.Json>) -> Maybe<&2, List<&2, String>>:
  match js:
    case Nil{}:
      Some{[]}
    case Con{head, rest}:
      Shard.cons(String, Json.as_str(head), Shard.strs.of(rest))

# js's elements when ok, else None
def Shard.arr.if(ok: Bool, js: Value.Json) -> Maybe<&2, List<&2, Value.Json>>:
  match ok:
    case True{}:
      Some{Json.items(js)}
    case False{}:
      None{}

# an array's elements, or None when it is not an array
def Shard.arr(+js: Value.Json) -> Maybe<&2, List<&2, Value.Json>>:
  Shard.arr.if(Json.is_arr(js), js)

# the items of an array of items, or None
def Shard.items.of_arr(
  got: Maybe<&2, List<&2, Value.Json>>
) -> Maybe<&2, List<&2, Item>>:
  match got:
    case None{}:
      None{}
    case Some{js}:
      Shard.items.of(js)

# the texts of an array of strings, or None
def Shard.strs.of_arr(
  got: Maybe<&2, List<&2, Value.Json>>
) -> Maybe<&2, List<&2, String>>:
  match got:
    case None{}:
      None{}
    case Some{js}:
      Shard.strs.of(js)

# the shard of the parts read, or None when one is missing
def Shard.of.go(
  num: Maybe<&2, U32>,
  items: Maybe<&2, List<&2, Item>>,
  sources: Maybe<&2, List<&2, String>>,
  chars: Maybe<&2, U32>,
  frozen: Maybe<&2, Bool>
) -> Maybe<&2, Shard>:
  match num items sources chars frozen:
    case Some{a} Some{b} Some{c} Some{d} Some{e}:
      Some{Shard{a, b, c, d, e}}
    case _ _ _ _ _:
      None{}

# a shard read from a parsed JSON object: None unless n and chars are
# numbers, items an array of items each with a record as Record.of_json
# reads it, sources an array of strings, and frozen a boolean
def Shard.of_value(+js: Value.Json) -> Maybe<&2, Shard>:
  Shard.of.go(Json.as_u32(Json.get(js, "n")),
    Shard.items.of_arr(Shard.arr(Json.get(js, "items"))),
    Shard.strs.of_arr(Shard.arr(Json.get(js, "sources"))),
    Json.as_u32(Json.get(js, "chars")), Json.as_bool(Json.get(js, "frozen")))

# a shard read from a parsed JSON text, or None when there is none
def Shard.of_parsed(parsed: Maybe<&2, Value.Json>) -> Maybe<&2, Shard>:
  match parsed:
    case None{}:
      None{}
    case Some{js}:
      Shard.of_value(js)

# a shard read from its JSON text, or None when the text is not one
def Shard.of_json(text: String) -> Maybe<&2, Shard>:
  Shard.of_parsed(Json.parse(text))

# the code points of the paragraph texts of ps
def Shard.texts(ps: List<&2, P.Para>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          Nat.add(String.length(text), Shard.texts(rest))

# the size of items: each item's record header line and paragraph texts
def Shard.size(its: List<&2, Item>) -> Nat:
  match its:
    case Nil{}:
      0n
    case Con{+it, rest}:
      match it:
        case Item{+rec, from, upto}:
          Nat.add(Nat.add(String.length(R.Record.header(rec)),
            Shard.texts(Shard.item.paras(Item{rec, from, upto}))),
            Shard.size(rest))

# the shards to write when records xs are appended after a tail: packing
# resumed from the tail, which is the open shard a pack ends with, so
# frozen shards are never packed again
def Shard.extend(+cap: U32, tail: Shard, xs: List<&2, R.Record>) -> List<&2, Shard>:
  match tail:
    case Shard{num, +items, _sources, _chars, _frozen}:
      Shard.number(Shard.run(xs, U32.to_nat(cap), Open{items, Shard.size(items)}),
        num)

# --- one source per shard ---

# a record's source
def Shard.src(rec: R.Record) -> String:
  match rec:
    case R.Record{_id, _ts, source, _author, _thread, _parent, _paras, _ptr}:
      source

# rec ahead of rest when keep
def Shard.only.if(keep: Bool, rec: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match keep:
    case True{}:
      rec <> rest
    case False{}:
      rest

# the records of xs whose source is src, in order: what the shards of src
# are packed from
def Shard.only(+src: String, xs: List<&2, R.Record>) -> List<&2, R.Record>:
  match xs:
    case Nil{}:
      []
    case Con{+rec, rest}:
      Shard.only.if(String.eq(Shard.src(rec), src), rec, Shard.only(src, rest))

# the sorted distinct sources of records
def Shard.keys(xs: List<&2, R.Record>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{rec, rest}:
      Shard.insert(Shard.keys(rest), Shard.src(rec))

# one source's records, in order
type Part is Data:
  Part{src: String, recs: List<&2, R.Record>}

# rec put into parts whose first is top's, by how its source src compared
# to top: a part of its own ahead, at the front of top's, or into the rest
def Shard.put.at(
  order: Cmp,
  rec: R.Record,
  src: String,
  top: String,
  grs: List<&2, R.Record>,
  rest: List<&2, Part>,
  ins: Unit -> List<&2, Part>
) -> List<&2, Part>:
  match order:
    case LT{}:
      Part{src, [rec]} <> Part{top, grs} <> rest
    case EQ{}:
      Part{top, rec <> grs} <> rest
    case GT{}:
      Part{top, grs} <> ins(Unit{})

# rec of source src put at the front of its part, the parts sorted by
# source
def Shard.put(ps: List<&2, Part>, +src: String, +rec: R.Record) -> List<&2, Part>:
  match ps:
    case Nil{}:
      [Part{src, [rec]}]
    case Con{p, +rest}:
      match p:
        case Part{+top, grs}:
          Shard.put.at(String.order(src, top), rec, src, top, grs, rest,
            _u => Shard.put(rest, src, rec))

# records split by source in one pass: one part per source, sorted by
# source, each holding that source's records in order
def Shard.parts(xs: List<&2, R.Record>) -> List<&2, Part>:
  match xs:
    case Nil{}:
      []
    case Con{+rec, rest}:
      Shard.put(Shard.parts(rest), Shard.src(rec), rec)

# recs ahead of rest when hit
def Shard.part.if(hit: Bool, recs: List<&2, R.Record>, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match hit:
    case True{}:
      List.append(&2, R.Record, recs, rest)
    case False{}:
      rest

# the records of the parts of source src, in order
def Shard.part(+src: String, ps: List<&2, Part>) -> List<&2, R.Record>:
  match ps:
    case Nil{}:
      []
    case Con{p, rest}:
      match p:
        case Part{g, recs}:
          Shard.part.if(String.eq(g, src), recs, Shard.part(src, rest))

# --- a source's directory name ---

# True when the code point chr is the text txt
def Shard.is(chr: Char, txt: String) -> Bool:
  String.eq(SCon{chr, SNil{}}, txt)

# a code point of a source in its directory name, ahead of rest: % / and .
# as %25 %2F %2E, any other as itself
def Shard.dir.ch(pct: Bool, sl: Bool, dot: Bool, chr: Char, rest: String) -> String:
  match pct sl dot:
    case True{} _ _:
      "%25" ++ rest
    case False{} True{} _:
      "%2F" ++ rest
    case False{} False{} True{}:
      "%2E" ++ rest
    case False{} False{} False{}:
      SCon{chr, rest}

# a source's directory name: the source with % / and . escaped as %25 %2F
# %2E, so the name holds no / or . and reads back with Shard.undir
def Shard.dir(src: String) -> String:
  match src:
    case SNil{}:
      ""
    case SCon{+chr, rest}:
      Shard.dir.ch(Shard.is(chr, "%"), Shard.is(chr, "/"), Shard.is(chr, "."), chr,
        Shard.dir(rest))

# where a read of a directory name is: on plain code points, after a %, or
# after a % and the first code point of its escape
type Pend is Data:
  Plain{}
  Pct{}
  Hex{hi: Char}

# the code point an escape stands for by which code it is, or None
def Shard.code.of(c25: Bool, c2f: Bool, c2e: Bool) -> Maybe<&2, Char>:
  match c25 c2f c2e:
    case True{} _ _:
      Some{'%'}
    case False{} True{} _:
      Some{'/'}
    case False{} False{} True{}:
      Some{'.'}
    case False{} False{} False{}:
      None{}

# the code point an escape %<hi><lo> stands for, or None
def Shard.code(+hi: Char, +lo: Char) -> Maybe<&2, Char>:
  +code = {SCon{hi, SCon{lo, SNil{}}} : String}
  Shard.code.of(String.eq(code, "25"), String.eq(code, "2F"), String.eq(code, "2E"))

# chr ahead of rest, or None when either is missing
def Shard.undir.cons(chr: Maybe<&2, Char>, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match chr rest:
    case Some{x} Some{r}:
      Some{SCon{x, r}}
    case _ _:
      None{}

# a plain code point chr ahead of rest: a % starts an escape, so rest is
# the whole read; a bare / or . is no directory name's
def Shard.undir.plain(pct: Bool, bad: Bool, chr: Char, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match pct bad:
    case True{} _:
      rest
    case False{} True{}:
      None{}
    case False{} False{}:
      Shard.undir.cons(Some{chr}, rest)

# what code point chr read at st gives ahead of rest, the read after it
def Shard.undir.out(st: Pend, +chr: Char, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match st:
    case Plain{}:
      Shard.undir.plain(Shard.is(chr, "%"), Bool.or(Shard.is(chr, "/"), Shard.is(chr, ".")),
        chr, rest)
    case Pct{}:
      rest
    case Hex{hi}:
      Shard.undir.cons(Shard.code(hi, chr), rest)

# where the read is after code point chr read at st
def Shard.undir.next(st: Pend, +chr: Char) -> Pend:
  match st:
    case Plain{}:
      Bool.pick(Pend, Shard.is(chr, "%"), Pct{}, Plain{})
    case Pct{}:
      Hex{chr}
    case Hex{_a}:
      Plain{}

# the end of a name read at st: whole only on plain code points
def Shard.undir.end(st: Pend) -> Maybe<&2, String>:
  match st:
    case Plain{}:
      Some{""}
    case _s:
      None{}

# the source of the name read from st, or None
def Shard.undir.go(name: String, +st: Pend) -> Maybe<&2, String>:
  match name:
    case SNil{}:
      Shard.undir.end(st)
    case SCon{+chr, rest}:
      Shard.undir.out(st, chr, Shard.undir.go(rest, Shard.undir.next(st, chr)))

# the source a directory name stands for, or None when it is no source's
# name: it holds a bare / or ., or a % not followed by 25, 2F or 2E
def Shard.undir(name: String) -> Maybe<&2, String>:
  Shard.undir.go(name, Plain{})
