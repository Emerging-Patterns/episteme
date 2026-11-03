# episteme/src/filter: a question's source filter and since, which shards
# it reads, which excerpts it keeps and whether it may be asked at all.
# Pure: no IO.
import Base
import ./shard.bend as S
import ./excerpt.bend as E

# one selector: a source value to equal, or a prefix to start with
type Sel is Data:
  Exact{text: String}
  Prefix{text: String}

# a non-empty piece as a selector: a prefix when it ends in /, else exact
def Filter.sel.if(piece: String, slash: Bool) -> Sel:
  match slash:
    case True{}:
      Prefix{piece}
    case False{}:
      Exact{piece}

# the selector of a piece ahead of rest, or rest when the piece is empty
def Filter.piece(+piece: String, rest: List<&2, Sel>) -> List<&2, Sel>:
  match piece:
    case SNil{}:
      rest
    case SCon{_h, _t}:
      Filter.sel.if(piece, String.ends_with(piece, "/")) <> rest

# the selectors of pieces ahead of rest, each with its surrounding
# whitespace trimmed
def Filter.pieces(ps: List<&2, String>, rest: List<&2, Sel>) -> List<&2, Sel>:
  match ps:
    case Nil{}:
      rest
    case Con{p, more}:
      Filter.piece(String.trim(p), Filter.pieces(more, rest))

# the --filter values as selectors: each split at commas, pieces trimmed,
# empty pieces dropped
def Filter.parse(args: List<&2, String>) -> List<&2, Sel>:
  match args:
    case Nil{}:
      []
    case Con{arg, more}:
      Filter.pieces(String.split(arg, ','), Filter.parse(more))

# True when sel selects the source src
def Filter.selects(sel: Sel, +src: String) -> Bool:
  match sel:
    case Exact{text}:
      String.eq(src, text)
    case Prefix{text}:
      String.starts_with(src, text)

# True when some selector of sels selects the source src
def Filter.picks(+sels: List<&2, Sel>, +src: String) -> Bool:
  match sels:
    case Nil{}:
      False{}
    case Con{sel, rest}:
      List.any.if(_u => Filter.picks(rest, src), Filter.selects(sel, src))

# True when a source directory is read: its name reads back
# (Shard.undir) as a source some selector of sels selects; a name that is
# no source's is never read
def Filter.reads.of(+sels: List<&2, Sel>, got: Maybe<&2, String>) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{+src}:
      Filter.picks(sels, src)

# True when ask reads the source directory named name
def Filter.reads(+sels: List<&2, Sel>, +name: String) -> Bool:
  Filter.reads.of(sels, S.Shard.undir(name))

# True when a shard with these sources is read: some selector of sels selects
# one of them
def Filter.hits(+sels: List<&2, Sel>, sources: List<&2, String>) -> Bool:
  match sources:
    case Nil{}:
      False{}
    case Con{src, rest}:
      List.any.if(_u => Filter.hits(sels, rest), Filter.picks(sels, src))

# the refusal: a question about chats names a project
def Filter.refusal() -> String:
  "a filter is required, and a chat filter must name a project; run \"episteme sources\" to list them"

# True when sel would select every Claude chat
def Filter.wide(sel: Sel) -> Bool:
  match sel:
    case Exact{text}:
      String.eq(text, "chat:claude")
    case Prefix{+text}:
      Bool.or(String.eq(text, "chat:"),
        Bool.or(String.eq(text, "chat:claude/"), String.eq(text, "")))

# True when some selector of sels would select every Claude chat
def Filter.any_wide(sels: List<&2, Sel>) -> Bool:
  match sels:
    case Nil{}:
      False{}
    case Con{sel, rest}:
      List.any.if(_u => Filter.any_wide(rest), Filter.wide(sel))

# Fail with the refusal when bad, else Done
def Filter.check.if(bad: Bool) -> Result<&2, &2, String, Unit>:
  match bad:
    case True{}:
      Fail{Filter.refusal()}
    case False{}:
      Done{Unit{}}

# Done, or Fail with the refusal when sels is empty or holds a selector that
# would select every Claude chat
def Filter.check(sels: List<&2, Sel>) -> Result<&2, &2, String, Unit>:
  match sels:
    case Nil{}:
      Fail{Filter.refusal()}
    case Con{sel, rest}:
      Filter.check.if(Filter.any_wide(sel <> rest))

# --- since ---

# True when ch fits the pattern code point pc: a digit for d, else pc itself
def Filter.fits.if(digit: Bool, ch: Char, pc: Char) -> Bool:
  match digit:
    case True{}:
      Char.is_digit(ch)
    case False{}:
      Char.is_eq(ch, pc)

# True when the text fits the pattern code point by code point
def Filter.shaped(text: String, pat: String) -> Bool:
  match text pat:
    case SNil{} SNil{}:
      True{}
    case SCon{ch, rest} SCon{+pc, more}:
      List.all.if(_u => Filter.shaped(rest, more), Filter.fits.if(Char.is_eq(pc, 'd'), ch, pc))
    case _ _:
      False{}

# the since of a date at midnight UTC, of a full time as it is, else None
def Filter.since.if(day: Bool, full: Bool, +text: String) -> Maybe<&2, String>:
  match day full:
    case True{} _:
      Some{text ++ "T00:00:00.000Z"}
    case False{} True{}:
      Some{text}
    case False{} False{}:
      None{}

# a --since value as a time to compare records' ts with: YYYY-MM-DD is its
# midnight UTC, YYYY-MM-DDTHH:MM:SS.mmmZ is kept, anything else is None
def Filter.since(+text: String) -> Maybe<&2, String>:
  Filter.since.if(Filter.shaped(text, "dddd-dd-dd"),
    Filter.shaped(text, "dddd-dd-ddTdd:dd:dd.dddZ"), text)

# the since read from a given value, or the refusal naming it
def Filter.since.at(got: Maybe<&2, String>, +arg: String) -> Result<&2, &2, String, Maybe<&2, String>>:
  match got:
    case None{}:
      Fail{"--since takes YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ, not " ++ arg}
    case Some{since}:
      Done{Some{since}}

# the --since value read: no since when none was given
def Filter.since.arg(arg: Maybe<&2, String>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match arg:
    case None{}:
      Done{None{}}
    case Some{+text}:
      Filter.since.at(Filter.since(text), text)

# True when some item of its holds a record at or after since
def Filter.newer(its: List<&2, S.Item>, +since: String) -> Bool:
  match its:
    case Nil{}:
      False{}
    case Con{it, rest}:
      match it:
        case S.Item{rec, _from, _upto}:
          List.any.if(_u => Filter.newer(rest, since),
            String.is_ge(E.Excerpt.ts(rec), since))

# True when the shard holds a record at or after since
def Filter.fresh(sh: S.Shard, +since: String) -> Bool:
  match sh:
    case S.Shard{_n, items, _sources, _chars, _frozen}:
      Filter.newer(items, since)

# the shards of ss, in order, that hold a record at or after since
def Filter.recent.go(ss: List<&2, S.Shard>, +since: String) -> List<&2, S.Shard>:
  match ss:
    case Nil{}:
      []
    case Con{+sh, rest}:
      List.filter.put(S.Shard, sh, Filter.recent.go(rest, since), Filter.fresh(sh, since))

# the shards a question with this since reads: all of ss without one
def Filter.recent(since: Maybe<&2, String>, ss: List<&2, S.Shard>) -> List<&2, S.Shard>:
  match since:
    case None{}:
      ss
    case Some{+t}:
      Filter.recent.go(ss, t)

# the excerpts of xs, in order, whose record is at or after since
def Filter.after.go(xs: List<&2, E.Ex>, +since: String) -> List<&2, E.Ex>:
  match xs:
    case Nil{}:
      []
    case Con{+x, rest}:
      List.filter.put(E.Ex, x, Filter.after.go(rest, since),
        String.is_ge(E.Excerpt.ts(E.Excerpt.rec(x)), since))

# the excerpts a question with this since delivers: all of xs without one
def Filter.after(since: Maybe<&2, String>, xs: List<&2, E.Ex>) -> List<&2, E.Ex>:
  match since:
    case None{}:
      xs
    case Some{+t}:
      Filter.after.go(xs, t)
