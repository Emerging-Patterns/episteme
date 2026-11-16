# episteme/src/para: a text split into numbered paragraphs, each with its
# code-point offsets in the text. Pure: no IO.
import Base

# one paragraph: its number (1 for the first), where it starts and ends in
# the text (code points, end exclusive), and its text, verbatim
type Para is Data:
  Para{n: U32, start: U32, end: U32, text: String}

# the longest paragraph text, in code points
def Para.max() -> U32:
  4000

# the line being read: the text from its start on, where it starts, how
# long it is so far, how many more code points fit before the limit, and
# whether every code point of it so far is whitespace (after a hard cut,
# the line is what follows the cut)
type Line is Data:
  Line{suf: String, start: U32, len: Nat, room: Nat, blank: Bool}

# the paragraph built from the lines before the current one: none, or the
# text from its start on, where it starts and ends, its length, and how
# many more code points the current line may grow by and still join it
type Block is Data:
  Shut{}
  Open{suf: String, start: U32, end: U32, len: Nat, room: Nat}

# the scan's state: the offset of the next code point, the paragraph being
# built and the line being read
type Scan is Data:
  Scan{off: U32, block: Block, line: Line}

# what one code point gives: the paragraphs it finishes, and the next state
type Step is Data:
  Step{out: List<&2, Para>, next: Scan}

# what the end of a line gives: the paragraphs it finishes, and the block
type Ended is Data:
  Ended{out: List<&2, Para>, block: Block}

# True when every code point of str is whitespace (an empty str is)
def Para.blank(str: String) -> Bool:
  match str:
    case SNil{}:
      True{}
    case SCon{head, tail}:
      List.all.if(_u => Para.blank(tail), Char.is_space(head))

# True for the line feed
def Para.is_nl(chr: Char) -> Bool:
  U32.is_eq(Char.to_u32(chr), 10)

# keep para ahead of ps unless its text is blank
def Para.emit.if(
  blank: Bool,
  para: Para,
  ps: List<&2, Para>
) -> List<&2, Para>:
  match blank:
    case True{}:
      ps
    case False{}:
      para <> ps

# the len code points at the head of suf, from start to end, ahead of ps,
# unless they are all whitespace
def Para.emit(
  suf: String,
  start: U32,
  end: U32,
  len: Nat,
  ps: List<&2, Para>
) -> List<&2, Para>:
  +text = String.take(suf, len)
  Para.emit.if(Para.blank(text), Para{0, start, end, text}, ps)

# the block's paragraph ahead of ps, if there is one
def Para.flush(block: Block, ps: List<&2, Para>) -> List<&2, Para>:
  match block:
    case Shut{}:
      ps
    case Open{suf, start, end, len, _room}:
      Para.emit(suf, start, end, len, ps)

# a non-blank line from lstart to off joins the block, or starts one when
# there is none or the line does not fit beside it
def Para.close.join(
  off: U32,
  block: Block,
  lsuf: String,
  lstart: U32,
  llen: Nat,
  lroom: Nat
) -> Ended:
  match block:
    case Shut{}:
      Ended{[], Open{lsuf, lstart, off, llen, lroom}}
    case Open{psuf, pstart, pend, plen, room}:
      match room:
        case 0n:
          Ended{Para.emit(psuf, pstart, pend, plen, []),
            Open{lsuf, lstart, off, llen, lroom}}
        case 1n+rest:
          Ended{[], Open{psuf, pstart, off, Nat.add(llen, 1n+plen), rest}}

# the end of the line ln at off: a blank line finishes the block, any other
# joins it
def Para.close(off: U32, block: Block, ln: Line) -> Ended:
  match ln:
    case Line{lsuf, lstart, llen, lroom, blank}:
      match blank:
        case True{}:
          Ended{Para.flush(block, []), Shut{}}
        case False{}:
          Para.close.join(off, block, lsuf, lstart, llen, lroom)

# a code point read while a block is open: the line still fits beside it,
# or the block is finished
def Para.grow.block(block: Block) -> Ended:
  match block:
    case Shut{}:
      Ended{[], Shut{}}
    case Open{psuf, pstart, pend, plen, room}:
      match room:
        case 0n:
          Ended{Para.emit(psuf, pstart, pend, plen, []), Shut{}}
        case 1n+0n:
          Ended{Para.emit(psuf, pstart, pend, plen, []), Shut{}}
        case 1n+1n+rest:
          Ended{[], Open{psuf, pstart, pend, plen, 1n+rest}}

# the rest of a line cut at the limit starts a new line at the code point
# chr, at off
def Para.grow.cut(
  cap: Nat,
  +off: U32,
  +chr: Char,
  tail: String,
  out: List<&2, Para>
) -> Step:
  match cap:
    case 1n+rest:
      Step{out, Scan{U32.inc(off), Shut{},
        Line{SCon{chr, tail}, off, 1n, rest, Char.is_space(chr)}}}
    case 0n:
      Step{out, Scan{U32.inc(off), Shut{},
        Line{tail, U32.inc(off), 0n, 0n, True{}}}}

# a code point chr at off, with tail after it, joins the line; a line
# already at the limit is cut there first, finishing the block too
def Para.grow.line(
  +cap: Nat,
  +off: U32,
  +chr: Char,
  tail: String,
  ended: Ended,
  ln: Line
) -> Step:
  match ended ln:
    case Ended{out, block} Line{lsuf, lstart, llen, lroom, blank}:
      match lroom:
        case 1n+rest:
          Step{out, Scan{U32.inc(off), block, Line{lsuf, lstart, 1n+llen, rest,
            Bool.and(blank, Char.is_space(chr))}}}
        case 0n:
          Para.grow.cut(cap, off, chr, tail,
            List.append(&2, Para, out,
              Para.flush(block, Para.emit(lsuf, lstart, off, llen, []))))

# a line feed at off ends the line; the next line starts after it
def Para.step.nl(+cap: Nat, +off: U32, tail: String, ended: Ended) -> Step:
  match ended:
    case Ended{out, block}:
      Step{out, Scan{U32.inc(off), block,
        Line{tail, U32.inc(off), 0n, cap, True{}}}}

# one code point chr, with tail after it; nl says whether chr is a line
# feed
def Para.step.if(
  nl: Bool,
  +cap: Nat,
  chr: Char,
  tail: String,
  st: Scan
) -> Step:
  match nl:
    case True{}:
      match st:
        case Scan{+off, block, ln}:
          Para.step.nl(cap, off, tail, Para.close(off, block, ln))
    case False{}:
      match st:
        case Scan{+off, block, ln}:
          Para.grow.line(cap, off, chr, tail, Para.grow.block(block), ln)

# one code point chr, with tail after it
def Para.step(+cap: Nat, +chr: Char, tail: String, st: Scan) -> Step:
  Para.step.if(Para.is_nl(chr), cap, chr, tail, st)

# the step's paragraphs, then what the rest of the scan gives from its state
def Para.then(step: Step, rest: Scan -> List<&2, Para>) -> List<&2, Para>:
  match step:
    case Step{out, next}:
      List.append(&2, Para, out, rest(next))

# what the end of the text gives: the block, after the last line ends
def Para.finish(ended: Ended) -> List<&2, Para>:
  match ended:
    case Ended{out, block}:
      List.append(&2, Para, out, Para.flush(block, []))

# the paragraphs, unnumbered, from the rest of the text with the state st
def Para.go(rest: String, +cap: Nat, st: Scan) -> List<&2, Para>:
  match rest:
    case SNil{}:
      match st:
        case Scan{off, block, ln}:
          Para.finish(Para.close(off, block, ln))
    case SCon{+chr, +tail}:
      Para.then(Para.step(cap, chr, tail, st),
        next => Para.go(tail, cap, next))

# number ps from num, in order
def Para.number(ps: List<&2, Para>, +num: U32) -> List<&2, Para>:
  match ps:
    case Nil{}:
      []
    case Con{para, rest}:
      match para:
        case Para{_n, start, end, text}:
          Para{num, start, end, text} <> Para.number(rest, U32.inc(num))

# the paragraphs of text: the maximal runs of non-blank lines, cut at the
# limit, numbered from 1
def Para.split(+text: String) -> List<&2, Para>:
  +cap = U32.to_nat(Para.max())
  Para.number(Para.go(text, cap,
    Scan{0, Shut{}, Line{text, 0, 0n, cap, True{}}}), 1)
