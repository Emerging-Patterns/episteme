# episteme/src/excerpt: a reader's labels turned into verbatim excerpts,
# excerpts merged across shards and rendered, and recall against gold spans
# for the eval. A reader's output is only compared with labels: every
# excerpt's record and text come from the shard. Pure: no IO.
import Base
import ./para.bend as P
import ./record.bend as R
import ./shard.bend as S

# paragraphs of one record, in order
type Ex is Data:
  Ex{rec: R.Record, paras: List<&2, P.Para>}

# a gold span for the eval: a source and whole-file code-point offsets,
# end exclusive
type Gold is Data:
  Gold{source: String, start: U32, end: U32}

# an excerpt's record
def Excerpt.rec(cur: Ex) -> R.Record:
  match cur:
    case Ex{rec, _paras}:
      rec

# an excerpt's paragraphs
def Excerpt.paras(cur: Ex) -> List<&2, P.Para>:
  match cur:
    case Ex{_rec, paras}:
      paras

# a record's id
def Excerpt.id(rec: R.Record) -> String:
  match rec:
    case R.Record{id, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
      id

# a record's timestamp
def Excerpt.ts(rec: R.Record) -> String:
  match rec:
    case R.Record{_id, ts, _source, _author, _thread, _parent, _paras, _ptr}:
      ts

# a record's source
def Excerpt.source(rec: R.Record) -> String:
  match rec:
    case R.Record{_id, _ts, source, _author, _thread, _parent, _paras, _ptr}:
      source

# a paragraph's number
def Excerpt.n(pa: P.Para) -> U32:
  match pa:
    case P.Para{n, _start, _end, _text}:
      n

# True when text is one of xs
def Excerpt.named(+text: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{head, rest}:
      List.any.if(_u => Excerpt.named(text, rest), String.eq(text, head))

# --- resolve ---

# the paragraphs of ps, labelled from p<idx> on, whose labels ls names
def Excerpt.pick(
  ps: List<&2, P.Para>,
  +idx: U32,
  +ls: List<&2, String>
) -> List<&2, P.Para>:
  match ps:
    case Nil{}:
      []
    case Con{pa, rest}:
      List.filter.put(P.Para, pa, Excerpt.pick(rest, U32.inc(idx), ls),
        Excerpt.named(S.Shard.label(idx), ls))

# the label number after ps, labelled from p<idx> on
def Excerpt.next(ps: List<&2, P.Para>, idx: U32) -> U32:
  match ps:
    case Nil{}:
      idx
    case Con{_pa, rest}:
      Excerpt.next(rest, U32.inc(idx))

# the excerpt of rec's paragraphs ps ahead of xs, or xs when ps is empty
def Excerpt.put(rec: R.Record, ps: List<&2, P.Para>, xs: List<&2, Ex>) -> List<&2, Ex>:
  match ps:
    case Nil{}:
      xs
    case Con{pa, rest}:
      Ex{rec, pa <> rest} <> xs

# one excerpt per item, of its paragraphs whose labels, counting from
# p<idx> across the items, ls names; items with none make none
def Excerpt.items(its: List<&2, S.Item>, +idx: U32, +ls: List<&2, String>) -> List<&2, Ex>:
  match its:
    case Nil{}:
      []
    case Con{it, rest}:
      match it:
        case S.Item{+rec, from, upto}:
          +ps = S.Shard.item.paras(S.Item{rec, from, upto})
          Excerpt.put(rec, Excerpt.pick(ps, idx, ls),
            Excerpt.items(rest, Excerpt.next(ps, idx), ls))

# True when text is the label of one of labels
def Excerpt.known(+text: String, labels: List<&2, S.Shard.Label()>) -> Bool:
  match labels:
    case Nil{}:
      False{}
    case Con{lab, rest}:
      match lab:
        case (l, _at):
          List.any.if(_u => Excerpt.known(text, rest), String.eq(text, l))

# 0 for a known label, 1 for an unknown one
def Excerpt.one(known: Bool) -> Nat:
  match known:
    case True{}:
      0n
    case False{}:
      1n

# how many of ls are the label of none of labels, each time one occurs
def Excerpt.strays(ls: List<&2, String>, +labels: List<&2, S.Shard.Label()>) -> Nat:
  match ls:
    case Nil{}:
      0n
    case Con{l, rest}:
      Nat.add(Excerpt.one(Excerpt.known(l, labels)),
        Excerpt.strays(rest, labels))

# a reader's labels on a shard as excerpts, one per item that holds a
# named paragraph, each of its named paragraphs in order with their record,
# taken from the shard; and how many of the labels the shard does not have
def Excerpt.resolve(+shard: S.Shard, +labels: List<&2, String>) -> List<&2, Ex> & U32:
  match shard:
    case S.Shard{_n, items, _sources, _chars, _frozen}:
      (Excerpt.items(items, 1, labels),
        U32.from_nat(Excerpt.strays(labels, S.Shard.labels(shard))))

# --- merge ---

# pa before qa and rest, in qa's place, or after qa, by how their numbers
# compare: then ins is rest with pa in its place
def Excerpt.place.at(
  order: Cmp,
  pa: P.Para,
  qa: P.Para,
  rest: List<&2, P.Para>,
  ins: List<&2, P.Para>
) -> List<&2, P.Para>:
  match order:
    case LT{}:
      pa <> qa <> rest
    case EQ{}:
      pa <> rest
    case GT{}:
      qa <> ins

# pa among qs, ascending by number: before the first with a larger number,
# in place of one with the same number
def Excerpt.place(+pa: P.Para, qs: List<&2, P.Para>) -> List<&2, P.Para>:
  match qs:
    case Nil{}:
      [pa]
    case Con{+qa, +rest}:
      Excerpt.place.at(U32.cmp(Excerpt.n(pa), Excerpt.n(qa)), pa, qa, rest,
        Excerpt.place(pa, rest))

# the paragraphs of ps placed among qs
def Excerpt.union(ps: List<&2, P.Para>, qs: List<&2, P.Para>) -> List<&2, P.Para>:
  match ps:
    case Nil{}:
      qs
    case Con{p, rest}:
      Excerpt.place(p, Excerpt.union(rest, qs))

# ps placed among acc when hit
def Excerpt.gather.if(hit: Bool, ps: List<&2, P.Para>, acc: List<&2, P.Para>) -> List<&2, P.Para>:
  match hit:
    case True{}:
      Excerpt.union(ps, acc)
    case False{}:
      acc

# the paragraphs of the excerpts of xs whose record id is id, ascending by
# number, each number once
def Excerpt.gather(+id: String, xs: List<&2, Ex>) -> List<&2, P.Para>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Excerpt.gather.if(String.eq(Excerpt.id(Excerpt.rec(x)), id),
        Excerpt.paras(x), Excerpt.gather(id, rest))

# cur ahead of rest unless seen
def Excerpt.firsts.if(seen: Bool, cur: Ex, rest: List<&2, Ex>) -> List<&2, Ex>:
  match seen:
    case True{}:
      rest
    case False{}:
      cur <> rest

# the first excerpt of each record id in xs whose id is not in seen, in order
def Excerpt.firsts(xs: List<&2, Ex>, +seen: List<&2, String>) -> List<&2, Ex>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      +id = Excerpt.id(Excerpt.rec(x))
      Excerpt.firsts.if(Excerpt.named(id, seen), x,
        Excerpt.firsts(rest, id <> seen))

# each excerpt of fs with its record's paragraphs gathered from all of xs
def Excerpt.join(fs: List<&2, Ex>, +xs: List<&2, Ex>) -> List<&2, Ex>:
  match fs:
    case Nil{}:
      []
    case Con{f, rest}:
      match f:
        case Ex{+rec, _paras}:
          Ex{rec, Excerpt.gather(Excerpt.id(rec), xs)} <> Excerpt.join(rest, xs)

# cur before other and rest when cur's ts is at most other's, else after
# other: then ins gives rest with cur in its place, built only when needed
def Excerpt.slot.if(
  first: Bool,
  cur: Ex,
  other: Ex,
  rest: List<&2, Ex>,
  ins: Unit -> List<&2, Ex>
) -> List<&2, Ex>:
  match first:
    case True{}:
      cur <> other <> rest
    case False{}:
      other <> ins(Unit{})

# cur among ys, which are ascending by ts: before the first whose ts is at
# least cur's
def Excerpt.slot(+cur: Ex, ys: List<&2, Ex>) -> List<&2, Ex>:
  match ys:
    case Nil{}:
      [cur]
    case Con{+other, +rest}:
      Excerpt.slot.if(String.is_le(Excerpt.ts(Excerpt.rec(cur)),
        Excerpt.ts(Excerpt.rec(other))), cur, other, rest, _u => Excerpt.slot(cur, rest))

# xs sorted by ts, stably: each is slotted ahead of the later ones
def Excerpt.sort(xs: List<&2, Ex>) -> List<&2, Ex>:
  match xs:
    case Nil{}:
      []
    case Con{x, rest}:
      Excerpt.slot(x, Excerpt.sort(rest))

# a run: a timestamp and the excerpts of it, in order
def Excerpt.Run() -> Data:
  Sigma<&2, &2, String, _t => List<&2, Ex>>

# cur ahead of the first run when it has cur's timestamp, else in a run of
# its own ahead of it
def Excerpt.group.if(
  same: Bool,
  +cur: Ex,
  time: String,
  run: List<&2, Ex>,
  more: List<&2, Excerpt.Run()>
) -> List<&2, Excerpt.Run()>:
  match same:
    case True{}:
      (time, cur <> run) <> more
    case False{}:
      (Excerpt.ts(Excerpt.rec(cur)), [cur]) <> (time, run) <> more

# cur ahead of the runs rs
def Excerpt.group.add(+cur: Ex, rs: List<&2, Excerpt.Run()>) -> List<&2, Excerpt.Run()>:
  match rs:
    case Nil{}:
      [(Excerpt.ts(Excerpt.rec(cur)), [cur])]
    case Con{first, more}:
      match first:
        case (+time, run):
          Excerpt.group.if(String.eq(Excerpt.ts(Excerpt.rec(cur)), time), cur,
            time, run, more)

# xs cut into runs of equal timestamps next to each other, in order
def Excerpt.group(xs: List<&2, Ex>) -> List<&2, Excerpt.Run()>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      Excerpt.group.add(x, Excerpt.group(rest))

# the excerpts of one timestamp as one excerpt per record id, in order of
# first appearance, its paragraphs gathered ascending by number, each once
def Excerpt.run(+xs: List<&2, Ex>) -> List<&2, Ex>:
  Excerpt.join(Excerpt.firsts(xs, []), xs)

# each run joined, in order
def Excerpt.joined(rs: List<&2, Excerpt.Run()>) -> List<&2, Ex>:
  match rs:
    case Nil{}:
      []
    case Con{first, more}:
      match first:
        case (_time, run):
          List.append(&2, Ex, Excerpt.run(run), Excerpt.joined(more))

# the excerpts of every shard, one list per shard in shard order, sorted
# stably by ts, then within each timestamp one excerpt per record id, its
# paragraphs gathered ascending by number, each number once: so in (ts,
# shard, paragraph) order. A record id has one ts, so it is joined across
# shards; the work beyond the sort is quadratic only within one timestamp
def Excerpt.merge(xs: List<&2, List<&2, Ex>>) -> List<&2, Ex>:
  Excerpt.joined(Excerpt.group(Excerpt.sort(List.concat(&2, Ex, xs))))

# --- render ---

# the paragraphs ps of record id, one line "<id>#<n>: <text>" each
def Excerpt.render.paras(+id: String, ps: List<&2, P.Para>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{pa, rest}:
      match pa:
        case P.Para{n, _start, _end, text}:
          String.concat([id, "#", U32.show(n), ": ", text, "\n",
            Excerpt.render.paras(id, rest)])

# a blank line when more excerpts follow
def Excerpt.render.gap(xs: List<&2, Ex>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{_head, _tail}:
      "\n"

# excerpts as text: each its line "### <id> | <source> | <ts> | <author>",
# then one line "<id>#<n>: <text>" per paragraph, apart by a blank line
def Excerpt.render(xs: List<&2, Ex>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, +rest}:
      match x:
        case Ex{rec, paras}:
          match rec:
            case R.Record{+id, ts, source, author, _thread, _parent, _rps, _ptr}:
              String.concat(["### ", id, " | ", source, " | ", ts, " | ",
                author, "\n", Excerpt.render.paras(id, paras),
                Excerpt.render.gap(rest), Excerpt.render(rest)])

# --- recall ---

# True when some paragraph of ps overlaps the span from lo to hi: start < hi
# and lo < end, in whole-file offsets
def Excerpt.hit(+lo: U32, +hi: U32, ps: List<&2, P.Para>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, start, end, _text}:
          List.any.if(_u => Excerpt.hit(lo, hi, rest),
            Bool.and(U32.is_lt(start, hi), U32.is_lt(lo, end)))

# True when some excerpt of xs has a record of source src and holds a
# paragraph that overlaps the span from lo to hi
def Excerpt.found(+src: String, +lo: U32, +hi: U32, xs: List<&2, Ex>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      match x:
        case Ex{rec, paras}:
          List.any.if(_u => Excerpt.found(src, lo, hi, rest),
            Bool.and(String.eq(Excerpt.source(rec), src),
              Excerpt.hit(lo, hi, paras)))

# True when the gold span is recalled: some excerpt's record has its source
# and holds a paragraph whose whole-file offsets overlap it
def Excerpt.recalled(gold: Gold, xs: List<&2, Ex>) -> Bool:
  match gold:
    case Gold{source, start, end}:
      Excerpt.found(source, start, end, xs)
