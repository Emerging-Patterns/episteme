# `Excerpt.resolve` returns exactly the shard's paragraphs whose labels the
# reader named, each once and in shard order, beside their records, with text
# taken from the shard (verbatim by construction); every label of the shard
# the reader named yields its paragraph; every excerpt holds a paragraph, one
# excerpt per item that holds a named paragraph, with the item's record; and
# the count is the number of the reader's labels the shard does not have,
# counting repeats.
#
# `src/excerpt.bend` turns a reader's labels into verbatim excerpts. An
# excerpt `Ex{rec, paras}` is paragraphs of one record. `Excerpt.resolve(s,
# labels)` walks the shard's paragraphs in order, labelled `p1`, `p2`, ... as
# `Shard.render` shows them, and keeps each paragraph whose label is among the
# reader's labels, beside its record, both taken from the shard: the reader's
# output is only ever compared with labels, never copied. A shard's paragraphs
# from one item make one excerpt, and an item with none kept makes none. It
# also counts the reader's labels the shard does not have, each time one
# occurs; a repeated known label adds nothing. A closed example resolves
# `["p2","p9","p2"]` on a shard of three paragraphs to one excerpt and one
# unknown label. `Excerpt.merge(xs)` takes one list per shard, in shard order.
# It sorts the excerpts stably by `rec.ts`, then within each timestamp joins
# the excerpts of one record id, from any shards, into one excerpt holding the
# record of the first of them and their paragraphs ascending by number, each
# number once (the first excerpt's copy wins). A record id has one `ts`, so
# this joins a record across shards, and the work beyond the sort is quadratic
# only within one timestamp. A closed example merges two shards that both hold
# record `a`, before `b` and `c` of one later `ts`. `ts` is ISO 8601 UTC, so
# string order is time order, and stability puts records of equal `ts` in
# shard order: together this is the `(ts, shard, paragraph)` order.
# `Excerpt.render` writes each excerpt as `### <id> | <source> | <ts> |
# <author>`, then `<id>#<n>: <text>` per paragraph, excerpts apart by a blank
# line; a closed example checks it, and no guarantee rests on it.
# `Excerpt.recalled(g, xs)` scores the eval: a gold span `Gold{source, start,
# end}` is recalled when some excerpt's record has `source` and holds a
# paragraph whose start/end offsets overlap the span, `start < g.end` and
# `g.start < end`; the paragraphs' start/end offsets are whole-file positions,
# as the books connector sets them with `Record.shift`
# (laws/ShiftMovesOffsets.bend, src/conn/books.bend); closed examples check an
# overlap, spans that only touch and another source.
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/excerpt.bend as E
import ./defs/ListMembership.bend as D1
import ./defs/Specification.bend as D2
import ./defs/UnknownLabels.bend as D3

# the record id of a paragraph beside its record
def ln.id(line: S.Shard.Line()) -> String:
  match line:
    case (r, _pa):
      D2.rec.id(r)

# the number of a paragraph beside its record
def ln.n(line: S.Shard.Line()) -> U32:
  match line:
    case (_r, pa):
      D2.para.n(pa)

# the excerpts resolve gives
def resolved(got: List<&2, E.Ex> & U32) -> List<&2, E.Ex>:
  match got:
    case (xs, _k):
      xs

# LAW: resolve keeps exactly the shard's paragraphs whose labels the reader
# named, each once and in shard order, beside their records, both taken
# from the shard: verbatim by construction
law resolve_lines:
  for +s: S.Shard
  for +ls: List<&2, String>
  {D2.lines(resolved(E.Excerpt.resolve(s, ls)))
    == D2.named(D2.items.cover(D2.shard.items(s)), 1, ls)
    : List<&2, S.Shard.Line()>}

# LAW: every label of the shard that the reader named yields its paragraph:
# a resolve that drops paragraphs cannot pass
law resolve_known:
  for +s: S.Shard
  for +ls: List<&2, String>
  for +l: String
  for +id: String
  for +n: U32
  for hl: {D2.mem(l, ls) == True{} : Bool}
  for hs: D1.Elem(S.Shard.Label(), (l, (id, n)), S.Shard.labels(s))
  exs line: S.Shard.Line()
  Pair(D1.Elem(S.Shard.Line(), line, D2.lines(resolved(E.Excerpt.resolve(s, ls)))),
    Pair({ln.id(line) == id : String}, {ln.n(line) == n : U32}))

# True when every excerpt of xs holds a paragraph
def filled(xs: List<&2, E.Ex>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{x, tail}:
      Bool.and(D2.full(D2.ex.paras(x)), filled(tail))

# LAW: every excerpt resolve gives holds a paragraph
law resolve_filled:
  for +s: S.Shard
  for +ls: List<&2, String>
  {filled(resolved(E.Excerpt.resolve(s, ls))) == True{} : Bool}

# True when the reader named one of the labels p<idx>, p<idx+1>, ... of ps
def any_named(ps: List<&2, P.Para>, +idx: U32, +ls: List<&2, String>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{_head, tail}:
      Bool.or(D2.mem(String.append("p", U32.show(idx)), ls),
        any_named(tail, U32.inc(idx), ls))

# rec ahead of rest when the reader named one of its item's paragraphs
def chosen.if(hit: Bool, rec: R.Record, rest: List<&2, R.Record>) -> List<&2, R.Record>:
  match hit:
    case True{}:
      rec <> rest
    case False{}:
      rest

# the records of the items its, labelled from p<idx> on, that hold a
# paragraph the reader named, in order, one per item
def chosen(its: List<&2, S.Item>, +idx: U32, +ls: List<&2, String>) -> List<&2, R.Record>:
  match its:
    case Nil{}:
      []
    case Con{+it, tail}:
      chosen.if(any_named(D2.item.paras(it), idx, ls), D2.item.rec(it),
        chosen(tail, D2.skip(D2.item.paras(it), idx), ls))

# LAW: resolve makes one excerpt per item that holds a paragraph the reader
# named, with the item's record, in shard order
law resolve_items:
  for +s: S.Shard
  for +ls: List<&2, String>
  {D2.recs(resolved(E.Excerpt.resolve(s, ls))) == chosen(D2.shard.items(s), 1, ls)
    : List<&2, R.Record>}

# k, one more when the label was unknown
def strays.if(known: Bool, count: Nat) -> Nat:
  match known:
    case True{}:
      count
    case False{}:
      1n+count

# how many of ls are the label of none of labels, each time one occurs
def strays(ls: List<&2, String>, +labels: List<&2, S.Shard.Label()>) -> Nat:
  match ls:
    case Nil{}:
      0n
    case Con{l, tail}:
      strays.if(D2.labelled(l, labels), strays(tail, labels))

# LAW: resolve counts the reader's labels the shard does not have, each
# time one occurs
law resolve_unknown:
  for +s: S.Shard
  for +ls: List<&2, String>
  {D3.unknown(E.Excerpt.resolve(s, ls))
    == U32.from_nat(strays(ls, S.Shard.labels(s))) : U32}
