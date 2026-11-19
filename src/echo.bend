# episteme/src/echo: which of the paragraphs a run's readers named are
# earlier askings of the question itself, and the reads without them
# (laws/AskingsArePassedOver.bend). Pure: no IO.
import Base
import ./para.bend as P
import ./shard.bend as S
import ./excerpt.bend as E
import ./read.bend as Rd

# a text's words from some place on, and whether that place is inside the
# first of them
type Scan is Data:
  Scan{open: Bool, ws: List<&2, String>}

# True for a letter a to z, in either case, and for a digit
def Echo.wordy(+ch: Char) -> Bool:
  Bool.or(Char.is_alpha(ch), Char.is_digit(ch))

# ch ahead of the words ws: the first letter of their first word when the
# text is inside it (open), else a word of its own ahead of them
def Echo.push(ch: Char, open: Bool, ws: List<&2, String>) -> List<&2, String>:
  match open ws:
    case True{} Con{w, rest}:
      SCon{ch, w} <> rest
    case True{} Nil{}:
      SCon{ch, SNil{}} <> []
    case False{} ws:
      SCon{ch, SNil{}} <> ws

# the scan of a text from ch on, given the scan after it: a letter or
# digit joins or starts the first word, in lower case, anything else ends it
def Echo.step(wordy: Bool, ch: Char, got: Scan) -> Scan:
  match wordy got:
    case True{} Scan{open, ws}:
      Scan{True{}, Echo.push(Char.to_lower(ch), open, ws)}
    case False{} Scan{_open, ws}:
      Scan{False{}, ws}

# the scan of a text
def Echo.scan(text: String) -> Scan:
  match text:
    case SNil{}:
      Scan{False{}, []}
    case SCon{+ch, rest}:
      Echo.step(Echo.wordy(ch), ch, Echo.scan(rest))

# the words of a scan
def Echo.scanned(got: Scan) -> List<&2, String>:
  match got:
    case Scan{_open, ws}:
      ws

# a text's words: its unbroken runs of letters and digits, in order, in
# lower case
def Echo.words(text: String) -> List<&2, String>:
  Echo.scanned(Echo.scan(text))

# True when the words q open the words pw: each is the word of pw in its
# place
def Echo.opens(q: List<&2, String>, pw: List<&2, String>) -> Bool:
  match q pw:
    case Nil{} _pw:
      True{}
    case Con{_w, _rest} Nil{}:
      False{}
    case Con{w, rest} Con{v, more}:
      List.all.if(_u => Echo.opens(rest, more), String.eq(w, v))

# True when the words q are in the words pw, all of them, in order and
# unbroken
def Echo.within(+q: List<&2, String>, pw: List<&2, String>) -> Bool:
  match pw:
    case Nil{}:
      Echo.opens(q, [])
    case Con{+v, +rest}:
      List.any.if(_u => Echo.within(q, rest), Echo.opens(q, v <> rest))

# the fewest words of a question a paragraph can hold: under it the same
# words in order may be a phrase, a heading or a sentence of the text's own
def Echo.least() -> Nat:
  8n

# True when a question of the words q has Echo.least() words or more
def Echo.long(q: List<&2, String>) -> Bool:
  Nat.is_le(Echo.least(), List.length(&2, String, q))

# the words of paragraphs' texts, in order
def Echo.said.paras(ps: List<&2, P.Para>) -> List<&2, String>:
  match ps:
    case Nil{}:
      []
    case Con{pa, rest}:
      match pa:
        case P.Para{_n, _start, _end, text}:
          List.append(&2, String, Echo.words(text), Echo.said.paras(rest))

# the words of excerpts' paragraphs, in order
def Echo.said.exs(xs: List<&2, E.Ex>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{x, rest}:
      List.append(&2, String, Echo.said.paras(E.Excerpt.paras(x)), Echo.said.exs(rest))

# the words of the paragraph a label names in a shard, none for a label the
# shard does not have
def Echo.said(sh: S.Shard, label: String) -> List<&2, String>:
  match sh:
    case S.Shard{_n, items, _sources, _chars, _frozen}:
      Echo.said.exs(E.Excerpt.items(items, 1, [label]))

# True when the paragraph a label names in a shard holds the question of
# the words q: q is long and within the paragraph's words. A short question
# reads no paragraph
def Echo.hit(+q: List<&2, String>, sh: S.Shard, label: String) -> Bool:
  List.all.if(_u => Echo.within(q, Echo.said(sh, label)), Echo.long(q))

# for each label of ls, whether its paragraph in the shard holds the
# question
def Echo.hits(+q: List<&2, String>, +sh: S.Shard, ls: List<&2, String>) -> List<&2, Bool>:
  match ls:
    case Nil{}:
      []
    case Con{l, rest}:
      Echo.hit(q, sh, l) <> Echo.hits(q, sh, rest)

# the xs whose place in hits is not a hit, in order; those past the end of
# hits are kept
def Echo.rest(-A: Data, xs: List<&2, A>, hits: List<&2, Bool>) -> List<&2, A>:
  match xs hits:
    case Nil{} _hits:
      []
    case Con{x, more} Nil{}:
      x <> more
    case Con{x, more} Con{hit, later}:
      List.filter.put(A, x, Echo.rest(A, more, later), Bool.not(hit))

# a read of the shard without its labels whose paragraph holds the
# question, each kept label with its rank
def Echo.read(+q: List<&2, String>, +sh: S.Shard, rd: Rd.Read) -> Rd.Read:
  match rd:
    case Rd.Read{shard, inst, +labels, ranks, ok, why, pn, pm, cn, ms}:
      +hits = Echo.hits(q, sh, labels)
      Rd.Read{shard, inst, Echo.rest(String, labels, hits), Echo.rest(U32, ranks, hits),
        ok, why, pn, pm, cn, ms}

# each read of rs, with the shard in its place of ss, without its labels
# whose paragraph holds the question; a read past the shards' end as it is
def Echo.reads(+q: List<&2, String>, rs: List<&2, Rd.Read>, ss: List<&2, S.Shard>) -> List<&2, Rd.Read>:
  match rs ss:
    case Nil{} _ss:
      []
    case Con{rd, more} Nil{}:
      rd <> more
    case Con{rd, more} Con{+sh, rest}:
      Echo.read(q, sh, rd) <> Echo.reads(q, more, rest)
