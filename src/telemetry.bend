# episteme/src/telemetry: one JSON line per question, what it asked and
# how its run went: the sources it hit and their sizes, each shard it read
# with the size that went in and what came out, and how long it took. It
# is appended to telemetry.jsonl under the store by src/ask.bend. Pure: no
# IO.
import Base
import ./shard.bend as S
import ./filter.bend as F
import ./excerpt.bend as E
import ./read.bend as Rd
import ./score.bend as Sc
import ./para.bend as P
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value

# one source's size among the shards a filter hits: its shards, their
# code points and their paragraphs
type Size is Data:
  Size{source: String, shards: U32, chars: U32, paras: Nat}

# a U32 as a JSON number
def Tele.u32(num: U32) -> Value.Json:
  Json.num(U32.show(num))

# a Nat as a JSON number
def Tele.nat(num: Nat) -> Value.Json:
  Json.num(Nat.show(num))

# a selector as it is written: a prefix ends in /, and keeps it
def Tele.sel(sel: F.Sel) -> Value.Json:
  match sel:
    case F.Exact{text}:
      Json.str(text)
    case F.Prefix{text}:
      Json.str(text)

# the selectors as JSON strings
def Tele.sels(sels: List<&2, F.Sel>) -> List<&2, Value.Json>:
  match sels:
    case Nil{}:
      []
    case Con{sel, rest}:
      Tele.sel(sel) <> Tele.sels(rest)

# the since, or null
def Tele.since(since: Maybe<&2, String>) -> Value.Json:
  match since:
    case None{}:
      Json.null()
    case Some{text}:
      Json.str(text)

# a shard's one source, or ""
def Tele.source(srcs: List<&2, String>) -> String:
  match srcs:
    case Nil{}:
      ""
    case Con{src, _rest}:
      src

# a shard's size added to the size ahead of the rest when it is of the
# same source, else a size of its own ahead of them
def Tele.add.if(same: Bool, +src: String, +chars: U32, +paras: Nat, top: Size, rest: List<&2, Size>) -> List<&2, Size>:
  match same:
    case True{}:
      match top:
        case Size{_src, shs, cs, ps}:
          Size{src, U32.inc(shs), U32.add(chars, cs), Nat.add(paras, ps)} <> rest
    case False{}:
      Size{src, 1, chars, paras} <> (top <> rest)

# a shard's size put ahead of the sizes of the shards after it
def Tele.add(+src: String, +chars: U32, +paras: Nat, szs: List<&2, Size>) -> List<&2, Size>:
  match szs:
    case Nil{}:
      [Size{src, 1, chars, paras}]
    case Con{top, rest}:
      match top:
        case Size{+tsrc, shs, cs, ps}:
          Tele.add.if(String.eq(src, tsrc), src, chars, paras, Size{tsrc, shs, cs, ps}, rest)

# how many paragraphs each shard holds, in order
def Tele.counts(ss: List<&2, S.Shard>) -> List<&2, Nat>:
  match ss:
    case Nil{}:
      []
    case Con{sh, rest}:
      Rd.Read.paras(sh) <> Tele.counts(rest)

# a shard of paras paragraphs added to the sizes szs of the shards after it
def Tele.put(sh: S.Shard, +paras: Nat, szs: List<&2, Size>) -> List<&2, Size>:
  match sh:
    case S.Shard{_n, _items, sources, chars, _frozen}:
      Tele.add(Tele.source(sources), chars, paras, szs)

# each source's size, in the shards' order, the shards beside their
# paragraph counts ps; a source's shards come together, as Store.shards
# answers them
def Tele.sizes(ss: List<&2, S.Shard>, ps: List<&2, Nat>) -> List<&2, Size>:
  match ss ps:
    case Con{sh, rest} Con{paras, more}:
      Tele.put(sh, paras, Tele.sizes(rest, more))
    case _ _:
      []

# a size as JSON
def Tele.size(sz: Size) -> Value.Json:
  match sz:
    case Size{source, shards, chars, paras}:
      Json.obj([("source", Json.str(source)), ("shards", Tele.u32(shards)),
        ("chars", Tele.u32(chars)), ("paras", Tele.nat(paras))])

# sizes as JSON
def Tele.size.all(szs: List<&2, Size>) -> List<&2, Value.Json>:
  match szs:
    case Nil{}:
      []
    case Con{sz, rest}:
      Tele.size(sz) <> Tele.size.all(rest)

# the read's fields: whether it answered, its milliseconds, the labels it
# named; a shard with no read did not answer
def Tele.read(got: Maybe<&2, Rd.Read>) -> List<&1, String & Value.Json>:
  match got:
    case None{}:
      [("ok", Json.bool(False{})), ("ms", Tele.u32(0)), ("labels", Tele.u32(0))]
    case Some{rd}:
      match rd:
        case Rd.Read{_shard, _inst, labels, ok, _why, _pn, _pm, _cn, ms}:
          [("ok", Json.bool(ok)), ("ms", Tele.u32(ms)),
            ("labels", Tele.nat(List.length(&2, String, labels)))]

# the paragraphs of excerpts
def Tele.paras(xs: List<&2, E.Ex>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{x, rest}:
      Nat.add(List.length(&2, P.Para, E.Excerpt.paras(x)), Tele.paras(rest))

# the paragraphs a shard's labels kept and their code points
def Tele.out(got: List<&2, E.Ex> & U32) -> List<&1, String & Value.Json>:
  (+xs, _unknown) = got
  [("out_paras", Tele.nat(Tele.paras(xs))), ("out_chars", Tele.nat(Sc.Score.chars(xs)))]

# a shard's code points
def Tele.chars.of(sh: S.Shard) -> U32:
  match sh:
    case S.Shard{_n, _items, _sources, chars, _frozen}:
      chars

# Tele.shard of the shard named source and n
def Tele.shard.at(source: String, num: U32, +sh: S.Shard, paras: Nat, +rs: List<&2, Rd.Read>) -> Value.Json:
  +got = Rd.Read.find(Rd.Read.n(sh), rs)
  name : List<&1, String & Value.Json> = [("source", Json.str(source)), ("n", Tele.u32(num)),
    ("chars", Tele.u32(Tele.chars.of(sh))), ("paras", Tele.nat(paras))]
  Json.obj(List.append(&1, String & Value.Json, name,
    List.append(&1, String & Value.Json, Tele.read(got),
      Tele.out(E.Excerpt.resolve(sh, Rd.Read.labels(got))))))

# a shard of the run as JSON: its own name, what went in (its code points
# and its paragraph count paras), its read, and what came out (the
# paragraphs its labels kept and their code points)
def Tele.shard(+sh: S.Shard, paras: Nat, nm: Rd.Name, +rs: List<&2, Rd.Read>) -> Value.Json:
  match nm:
    case Rd.Name{source, num}:
      Tele.shard.at(source, num, sh, paras, rs)

# the run's shards as JSON, beside their paragraph counts and their own
# names, in run order
def Tele.shards(
  hits: List<&2, S.Shard>,
  ps: List<&2, Nat>,
  names: List<&2, Rd.Name>,
  +rs: List<&2, Rd.Read>
) -> List<&2, Value.Json>:
  match hits ps names:
    case Con{sh, more} Con{paras, later} Con{nm, rest}:
      Tele.shard(sh, paras, nm, rs) <> Tele.shards(more, later, rest, rs)
    case _ _ _:
      []

# the code points of shards
def Tele.chars(ss: List<&2, S.Shard>) -> Nat:
  match ss:
    case Nil{}:
      0n
    case Con{sh, rest}:
      match sh:
        case S.Shard{_n, _items, _sources, chars, _frozen}:
          Nat.add(U32.to_nat(chars), Tele.chars(rest))

# a question's telemetry line: when it was asked and by which command
# (via), the question, its filter and since, its milliseconds, its exit
# code and refusal ("" when it ran), the size of every source the filter
# hits (all, before the since, beside their paragraph counts ap), each
# shard the run read (hits, numbered for the run, beside their paragraph
# counts hp and names, with reads rs), and the run's totals: code points
# in, excerpts and code points out. The counts are given, not counted, so
# a shard the question did not load is listed with the count its source's
# size index holds
def Tele.line.with(
  ts: String,
  via: String,
  question: String,
  filter: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  ms: Nat,
  code: U32,
  why: String,
  all: List<&2, S.Shard>,
  ap: List<&2, Nat>,
  +hits: List<&2, S.Shard>,
  hp: List<&2, Nat>,
  names: List<&2, Rd.Name>,
  +rs: List<&2, Rd.Read>,
  +xs: List<&2, E.Ex>
) -> String:
  Json.print(Json.obj([("ts", Json.str(ts)), ("via", Json.str(via)),
    ("question", Json.str(question)), ("filter", Json.arr(Tele.sels(filter))),
    ("since", Tele.since(since)), ("ms", Tele.nat(ms)), ("code", Tele.u32(code)),
    ("refused", Json.str(why)),
    ("sources", Json.arr(Tele.size.all(Tele.sizes(all, ap)))),
    ("shards", Json.arr(Tele.shards(hits, hp, names, rs))),
    ("in_chars", Tele.nat(Tele.chars(hits))),
    ("excerpts", Tele.nat(List.length(&2, E.Ex, xs))),
    ("out_chars", Tele.nat(Sc.Score.chars(xs)))]))

# Tele.line.with, each shard's paragraphs counted from the shard
def Tele.line(
  ts: String,
  via: String,
  question: String,
  filter: List<&2, F.Sel>,
  since: Maybe<&2, String>,
  ms: Nat,
  code: U32,
  why: String,
  +all: List<&2, S.Shard>,
  +hits: List<&2, S.Shard>,
  names: List<&2, Rd.Name>,
  +rs: List<&2, Rd.Read>,
  +xs: List<&2, E.Ex>
) -> String:
  Tele.line.with(ts, via, question, filter, since, ms, code, why, all, Tele.counts(all),
    hits, Tele.counts(hits), names, rs, xs)
