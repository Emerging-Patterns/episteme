# proofs of laws/ResolveKeepsNamedParagraphs.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/shard.bend as S
import ../src/excerpt.bend as E
import ../laws/ShardLabelsNumberParagraphs.bend as L1
import ../laws/ResolveKeepsNamedParagraphs.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ../laws/defs/Specification.bend as D2
import ./lemmas/CoverAndLabels.bend as M1
import ./lemmas/OffsetsHeld.bend as M2
import ./lemmas/ParagraphBesideRecord.bend as M3

# the excerpt of qs put ahead of xs adds its lines ahead of theirs
def put_lines(
  -rec: R.Record,
  qs: List<&2, P.Para>,
  -xs: List<&2, E.Ex>
) -> {D2.lines(E.Excerpt.put(rec, qs, xs))
  == List.append(&2, S.Shard.Line(), D2.pairs(rec, qs), D2.lines(xs))
  : List<&2, S.Shard.Line()>}:
  match qs:
    case Nil{}:
      {==}
    case Con{_pa, _rest}:
      {==}

# a line the reader named or not, either way as pick keeps its paragraph
def named_at(
  b: Bool,
  -rec: R.Record,
  -pa: P.Para,
  -x: List<&2, S.Shard.Line()>,
  -kept: List<&2, P.Para>,
  -y: List<&2, S.Shard.Line()>,
  e: {x == List.append(&2, S.Shard.Line(), D2.pairs(rec, kept), y) : List<&2, S.Shard.Line()>}
) -> {D2.named.if(b, (rec, pa), x)
  == List.append(&2, S.Shard.Line(),
    D2.pairs(rec, List.filter.put(P.Para, pa, kept, b)), y)
  : List<&2, S.Shard.Line()>}:
  match b:
    case True{}:
      Equal.cong(List<&2, S.Shard.Line()>, List<&2, S.Shard.Line()>,
        z => (rec, pa) <> z, x,
        List.append(&2, S.Shard.Line(), D2.pairs(rec, kept), y), e)
    case False{}:
      e

# the named lines of one record's paragraphs and then more are the
# paragraphs pick keeps, then the named lines of more
law named_app:
  for +rec: R.Record
  for ps: List<&2, P.Para>
  for +more: List<&2, S.Shard.Line()>
  for +idx: U32
  for +ls: List<&2, String>
  {D2.named(List.append(&2, S.Shard.Line(), D2.pairs(rec, ps), more), idx, ls)
    == List.append(&2, S.Shard.Line(),
      D2.pairs(rec, E.Excerpt.pick(ps, idx, ls)),
      D2.named(more, E.Excerpt.next(ps, idx), ls))
    : List<&2, S.Shard.Line()>}

def named_app(rec, ps, more, idx, ls):
  match ps:
    case Nil{}:
      {==}
    case Con{+pa, +rest}:
      %Equal.sym(Bool, E.Excerpt.named(S.Shard.label(idx), ls),
        D2.mem(String.append("p", U32.show(idx)), ls),
        M2.named_mem(S.Shard.label(idx), ls))
        : {D2.named.if(D2.mem(String.append("p", U32.show(idx)), ls),
          (rec, pa), D2.named(List.append(&2, S.Shard.Line(),
            D2.pairs(rec, rest), more), U32.inc(idx), ls))
          == List.append(&2, S.Shard.Line(), D2.pairs(rec,
            List.filter.put(P.Para, pa, E.Excerpt.pick(rest, U32.inc(idx), ls),
              _)), D2.named(more, E.Excerpt.next(rest, U32.inc(idx)), ls))
          : List<&2, S.Shard.Line()>}
      named_at(D2.mem(String.append("p", U32.show(idx)), ls), rec, pa,
        D2.named(List.append(&2, S.Shard.Line(), D2.pairs(rec, rest), more),
          U32.inc(idx), ls),
        E.Excerpt.pick(rest, U32.inc(idx), ls),
        D2.named(more, E.Excerpt.next(rest, U32.inc(idx)), ls),
        named_app(rec, rest, more, U32.inc(idx), ls))

# the excerpts of items, labelled from idx on, hold the named lines
law items_lines:
  for its: List<&2, S.Item>
  for +idx: U32
  for +ls: List<&2, String>
  {D2.lines(E.Excerpt.items(its, idx, ls))
    == D2.named(D2.items.cover(its), idx, ls) : List<&2, S.Shard.Line()>}

def items_lines(its, idx, ls):
  match its:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case S.Item{rec, +from, +upto}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
              +r = {R.Record{id, ts, source, author, thread, parent, paras, ptr} : R.Record}
              +ps = S.Shard.item.paras(S.Item{r, from, upto})
              %Equal.sym(List<&2, S.Shard.Line()>,
                D2.lines(E.Excerpt.put(r, E.Excerpt.pick(ps, idx, ls),
                  E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls))),
                List.append(&2, S.Shard.Line(),
                  D2.pairs(r, E.Excerpt.pick(ps, idx, ls)),
                  D2.lines(E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls))),
                put_lines(r, E.Excerpt.pick(ps, idx, ls),
                  E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls)))
                : {_ == D2.named(D2.items.cover(S.Item{r, from, upto} <> rest),
                  idx, ls) : List<&2, S.Shard.Line()>}
              %Equal.sym(List<&2, S.Shard.Line()>,
                D2.lines(E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls)),
                D2.named(D2.items.cover(rest), E.Excerpt.next(ps, idx), ls),
                items_lines(rest, E.Excerpt.next(ps, idx), ls))
                : {List.append(&2, S.Shard.Line(),
                  D2.pairs(r, E.Excerpt.pick(ps, idx, ls)), _)
                  == D2.named(D2.items.cover(S.Item{r, from, upto} <> rest),
                  idx, ls) : List<&2, S.Shard.Line()>}
              Equal.sym(List<&2, S.Shard.Line()>,
                D2.named(List.append(&2, S.Shard.Line(), D2.pairs(r, ps),
                  D2.items.cover(rest)), idx, ls),
                List.append(&2, S.Shard.Line(),
                  D2.pairs(r, E.Excerpt.pick(ps, idx, ls)),
                  D2.named(D2.items.cover(rest), E.Excerpt.next(ps, idx), ls)),
                named_app(r, ps, D2.items.cover(rest), idx, ls))

def Laws.resolve_lines(s, ls):
  match s:
    case S.Shard{_n, +items, _sources, _chars, _frozen}:
      items_lines(items, 1, ls)

# the excerpt of qs put ahead of xs holds a paragraph when qs does, and
# none when qs is empty
def put_filled(
  -rec: R.Record,
  qs: List<&2, P.Para>,
  -xs: List<&2, E.Ex>,
  e: {Laws.filled(xs) == True{} : Bool}
) -> {Laws.filled(E.Excerpt.put(rec, qs, xs)) == True{} : Bool}:
  match qs:
    case Nil{}:
      e
    case Con{_pa, _rest}:
      e

# every excerpt of items holds a paragraph
law items_filled:
  for its: List<&2, S.Item>
  for +idx: U32
  for +ls: List<&2, String>
  {Laws.filled(E.Excerpt.items(its, idx, ls)) == True{} : Bool}

def items_filled(its, idx, ls):
  match its:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case S.Item{+rec, +from, +upto}:
          +ps = S.Shard.item.paras(S.Item{rec, from, upto})
          put_filled(rec, E.Excerpt.pick(ps, idx, ls),
            E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls),
            items_filled(rest, E.Excerpt.next(ps, idx), ls))

def Laws.resolve_filled(s, ls):
  match s:
    case S.Shard{_n, +items, _sources, _chars, _frozen}:
      items_filled(items, 1, ls)

# the code's label count after a run of paragraphs is the specification's
law next_skip:
  for ps: List<&2, P.Para>
  for idx: U32
  {E.Excerpt.next(ps, idx) == D2.skip(ps, idx) : U32}

def next_skip(ps, idx):
  match ps:
    case Nil{}:
      {==}
    case Con{_pa, rest}:
      next_skip(rest, U32.inc(idx))

# a pick keeps a paragraph or not, either way as any_named says
def pick_full.at(
  b: Bool,
  -pa: P.Para,
  -kept: List<&2, P.Para>,
  -more: Bool,
  e: {D2.full(kept) == more : Bool}
) -> {D2.full(List.filter.put(P.Para, pa, kept, b)) == Bool.or(b, more) : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      e

# pick keeps a paragraph exactly when the reader named one of their labels
law pick_full:
  for ps: List<&2, P.Para>
  for +idx: U32
  for +ls: List<&2, String>
  {D2.full(E.Excerpt.pick(ps, idx, ls)) == Laws.any_named(ps, idx, ls) : Bool}

def pick_full(ps, idx, ls):
  match ps:
    case Nil{}:
      {==}
    case Con{+pa, +rest}:
      %Equal.sym(Bool, E.Excerpt.named(S.Shard.label(idx), ls),
        D2.mem(String.append("p", U32.show(idx)), ls),
        M2.named_mem(S.Shard.label(idx), ls))
        : {D2.full(List.filter.put(P.Para, pa, E.Excerpt.pick(rest, U32.inc(idx), ls), _))
          == Laws.any_named(pa <> rest, idx, ls) : Bool}
      pick_full.at(D2.mem(String.append("p", U32.show(idx)), ls), pa,
        E.Excerpt.pick(rest, U32.inc(idx), ls),
        Laws.any_named(rest, U32.inc(idx), ls), pick_full(rest, U32.inc(idx), ls))

# the excerpt of qs put ahead of xs adds its record ahead of theirs when qs
# holds a paragraph
def put_recs(
  +rec: R.Record,
  qs: List<&2, P.Para>,
  -xs: List<&2, E.Ex>
) -> {D2.recs(E.Excerpt.put(rec, qs, xs))
  == Laws.chosen.if(D2.full(qs), rec, D2.recs(xs)) : List<&2, R.Record>}:
  match qs:
    case Nil{}:
      {==}
    case Con{_pa, _rest}:
      {==}

# the records of the excerpts of items are the picked items' records
law items_recs:
  for its: List<&2, S.Item>
  for +idx: U32
  for +ls: List<&2, String>
  {D2.recs(E.Excerpt.items(its, idx, ls)) == Laws.chosen(its, idx, ls)
    : List<&2, R.Record>}

def items_recs(its, idx, ls):
  match its:
    case Nil{}:
      {==}
    case Con{it, +rest}:
      match it:
        case S.Item{rec, +from, +upto}:
          match rec:
            case R.Record{+id, +ts, +source, +author, +thread, +parent, +paras, +ptr}:
              +r = {R.Record{id, ts, source, author, thread, parent, paras, ptr} : R.Record}
              +ps = S.Shard.item.paras(S.Item{r, from, upto})
              %Equal.sym(List<&2, R.Record>,
                D2.recs(E.Excerpt.put(r, E.Excerpt.pick(ps, idx, ls),
                  E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls))),
                Laws.chosen.if(D2.full(E.Excerpt.pick(ps, idx, ls)), r,
                  D2.recs(E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls))),
                put_recs(r, E.Excerpt.pick(ps, idx, ls),
                  E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls)))
                : {_ == Laws.chosen(S.Item{r, from, upto} <> rest, idx, ls)
                  : List<&2, R.Record>}
              %Equal.sym(Bool, D2.full(E.Excerpt.pick(ps, idx, ls)),
                Laws.any_named(ps, idx, ls), pick_full(ps, idx, ls))
                : {Laws.chosen.if(_, r,
                  D2.recs(E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls)))
                  == Laws.chosen(S.Item{r, from, upto} <> rest, idx, ls)
                  : List<&2, R.Record>}
              %Equal.sym(List<&2, R.Record>,
                D2.recs(E.Excerpt.items(rest, E.Excerpt.next(ps, idx), ls)),
                Laws.chosen(rest, E.Excerpt.next(ps, idx), ls),
                items_recs(rest, E.Excerpt.next(ps, idx), ls))
                : {Laws.chosen.if(Laws.any_named(ps, idx, ls), r, _)
                  == Laws.chosen(S.Item{r, from, upto} <> rest, idx, ls)
                  : List<&2, R.Record>}
              %Equal.sym(U32, E.Excerpt.next(ps, idx), D2.skip(ps, idx),
                next_skip(ps, idx))
                : {Laws.chosen.if(Laws.any_named(ps, idx, ls), r,
                  Laws.chosen(rest, _, ls))
                  == Laws.chosen(S.Item{r, from, upto} <> rest, idx, ls)
                  : List<&2, R.Record>}
              {==}

def Laws.resolve_items(s, ls):
  match s:
    case S.Shard{_n, +items, _sources, _chars, _frozen}:
      items_recs(items, 1, ls)

# the code's known-label test is the specification's
law known_eq:
  for +text: String
  for labels: List<&2, S.Shard.Label()>
  {E.Excerpt.known(text, labels) == D2.labelled(text, labels) : Bool}

def known_eq(text, labels):
  match labels:
    case Nil{}:
      {==}
    case Con{lab, rest}:
      match lab:
        case (+l, _at):
          M2.any_if_or(String.eq(text, l), E.Excerpt.known(text, rest),
            D2.labelled(text, rest), known_eq(text, rest))

# one more for an unknown label, by either count
def strays_at(
  b: Bool,
  -x: Nat,
  -y: Nat,
  e: {x == y : Nat}
) -> {Nat.add(E.Excerpt.one(b), x) == Laws.strays.if(b, y) : Nat}:
  match b:
    case True{}:
      e
    case False{}:
      Equal.cong(Nat, Nat, k => 1n+k, x, y, e)

# the code's count of unknown labels is the specification's
law strays_eq:
  for ls: List<&2, String>
  for +labels: List<&2, S.Shard.Label()>
  {E.Excerpt.strays(ls, labels) == Laws.strays(ls, labels) : Nat}

def strays_eq(ls, labels):
  match ls:
    case Nil{}:
      {==}
    case Con{+l, rest}:
      %Equal.sym(Bool, E.Excerpt.known(l, labels), D2.labelled(l, labels),
        known_eq(l, labels))
        : {Nat.add(E.Excerpt.one(_), E.Excerpt.strays(rest, labels))
          == Laws.strays.if(D2.labelled(l, labels), Laws.strays(rest, labels))
          : Nat}
      strays_at(D2.labelled(l, labels), E.Excerpt.strays(rest, labels),
        Laws.strays(rest, labels), strays_eq(rest, labels))

def Laws.resolve_unknown(s, ls):
  match s:
    case S.Shard{+n, +items, +sources, +chars, +frozen}:
      Equal.cong(Nat, U32, k => U32.from_nat(k),
        E.Excerpt.strays(ls, S.Shard.labels(S.Shard{n, items, sources, chars,
          frozen})),
        Laws.strays(ls, S.Shard.labels(S.Shard{n, items, sources, chars,
          frozen})),
        strays_eq(ls, S.Shard.labels(S.Shard{n, items, sources, chars, frozen})))

# what is among the lines after a line is among them with it ahead, named
# or not
def got_if(
  b: Bool,
  -id: String,
  -n: U32,
  -line: S.Shard.Line(),
  -xs: List<&2, S.Shard.Line()>,
  g: M3.got(id, n, xs)
) -> M3.got(id, n, D2.named.if(b, line, xs)):
  match b:
    case True{}:
      match g:
        case (w, p):
          match p:
            case (el, q):
              (w, (Inr{el}, q))
    case False{}:
      g

# a label's text
def lab.l(x: S.Shard.Label()) -> String:
  match x:
    case (l, _at):
      l

# a label's record id
def lab.id(x: S.Shard.Label()) -> String:
  match x:
    case (_l, at):
      match at:
        case (i, _k):
          i

# a label's paragraph number
def lab.n(x: S.Shard.Label()) -> U32:
  match x:
    case (_l, at):
      match at:
        case (_i, k):
          k

# a named label among the tags of lines yields its line among the named ones
law known_named:
  for ps: List<&2, S.Shard.Line()>
  for +idx: U32
  for +ls: List<&2, String>
  for +l: String
  for +id: String
  for +n: U32
  for hl: {D2.mem(l, ls) == True{} : Bool}
  for hs: D1.Elem(S.Shard.Label(), (l, (id, n)), L1.tags(ps, idx))
  M3.got(id, n, D2.named(ps, idx, ls))

def known_named(ps, idx, ls, l, id, n, hl, hs):
  match ps:
    case Nil{}:
      Empty.absurd(M3.got(id, n, []), hs)
    case Con{line, +rest}:
      match line:
        case (+r, +pa):
          match hs:
            case Inl{+e}:
              +lb = String.append("p", U32.show(idx))
              +el = Equal.cong(S.Shard.Label(), String, x => lab.l(x),
                (l, (id, n)), (lb, (D2.rec.id(r), D2.para.n(pa))), e)
              +ei = Equal.cong(S.Shard.Label(), String, x => lab.id(x),
                (l, (id, n)), (lb, (D2.rec.id(r), D2.para.n(pa))), e)
              +en = Equal.cong(S.Shard.Label(), U32, x => lab.n(x),
                (l, (id, n)), (lb, (D2.rec.id(r), D2.para.n(pa))), e)
              +hb = {(%el : {D2.mem(_, ls) == True{} : Bool}
                hl) : {D2.mem(lb, ls) == True{} : Bool}}
              %Equal.sym(Bool, D2.mem(lb, ls), True{}, hb)
                : M3.got(id, n, D2.named.if(_, (r, pa),
                  D2.named(rest, U32.inc(idx), ls)))
              ((r, pa), (Inl{{==}}, (Equal.sym(String, id, D2.rec.id(r), ei),
                Equal.sym(U32, n, D2.para.n(pa), en))))
            case Inr{h2}:
              got_if(D2.mem(String.append("p", U32.show(idx)), ls), id, n, (r, pa),
                D2.named(rest, U32.inc(idx), ls),
                known_named(rest, U32.inc(idx), ls, l, id, n, hl, h2))

def Laws.resolve_known(s, ls, l, id, n, hl, hs):
  match s:
    case S.Shard{+sn, +items, +sources, +chars, +frozen}:
      %Equal.sym(List<&2, S.Shard.Line()>,
        D2.lines(E.Excerpt.items(items, 1, ls)),
        D2.named(D2.items.cover(items), 1, ls), items_lines(items, 1, ls))
        : M3.got(id, n, _)
      known_named(D2.items.cover(items), 1, ls, l, id, n, hl,
        M2.elem_cast(S.Shard.Label(), (l, (id, n)),
          S.Shard.labels(S.Shard{sn, items, sources, chars, frozen}),
          L1.tags(D2.items.cover(items), 1),
          L1.labels_cover(S.Shard{sn, items, sources, chars, frozen}), hs))
