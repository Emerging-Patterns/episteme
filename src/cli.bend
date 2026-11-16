# episteme/src/cli: the pure parts of the command line: its spec and
# version, the counts `episteme sources` prints, which record and paragraphs
# `episteme show` wants, a command's output as a show, and the input schemas
# of the tools `episteme serve` serves.
# Pure: no IO.
import Base
import ./para.bend as P
import ./record.bend as R
import ./shard.bend as S
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value
import shake@0.9.0.0/main.bend as Shake

# the package version marker
def Cli.version() -> String:
  "0.1.0"

# a text cut in two at a separator: what is before it and after it
type Cut is Data:
  Cut{before: String, after: String}

# one source's counts: records, paragraphs, and shards it is in
type Stat is Data:
  Stat{source: String, records: U32, paras: U32, shards: U32}

# 1 for True, 0 for False
def Cli.first.if(one: Bool) -> U32:
  match one:
    case True{}:
      1
    case False{}:
      0

# 1 when the paragraphs start with the record's first, else 0
def Cli.first(ps: List<&2, P.Para>) -> U32:
  match ps:
    case Nil{}:
      0
    case Con{pa, _rest}:
      match pa:
        case P.Para{n, _start, _end, _text}:
          Cli.first.if(U32.is_eq(n, 1))

# stat with counts added
def Cli.stat.add(st: Stat, +recs: U32, +ps: U32, +shs: U32) -> Stat:
  match st:
    case Stat{source, records, paras, shards}:
      Stat{source, U32.add(records, recs), U32.add(paras, ps), U32.add(shards, shs)}

# where src goes against the stat st: before it, in it, or after it,
# where later puts it in the rest
def Cli.stat.at(
  cmp: Cmp,
  +st: Stat,
  rest: List<&2, Stat>,
  +src: String,
  +recs: U32,
  +ps: U32,
  +shs: U32,
  later: Unit -> List<&2, Stat>
) -> List<&2, Stat>:
  match cmp:
    case LT{}:
      Stat{src, recs, ps, shs} <> st <> rest
    case EQ{}:
      Cli.stat.add(st, recs, ps, shs) <> rest
    case GT{}:
      st <> later(Unit{})

# the stat of src at its place in sts, kept in source order, with counts
# added; a new source starts at 0
def Cli.stat.put(sts: List<&2, Stat>, +src: String, +recs: U32, +ps: U32, +shs: U32) -> List<&2, Stat>:
  match sts:
    case Nil{}:
      [Stat{src, recs, ps, shs}]
    case Con{+st, +rest}:
      match st:
        case Stat{+source, _r, _p, _s}:
          Cli.stat.at(String.order(src, source), st, rest, src, recs, ps, shs,
            _u => Cli.stat.put(rest, src, recs, ps, shs))

# the counts of one item, of rec from from to upto, added
def Cli.stat.item(+rec: R.Record, from: U32, upto: U32, sts: List<&2, Stat>) -> List<&2, Stat>:
  match rec:
    case R.Record{_id, _ts, +source, _author, _thread, _parent, _paras, _ptr}:
      +ps = S.Shard.item.paras(S.Item{rec, from, upto})
      Cli.stat.put(sts, source, Cli.first(ps), U32.from_nat(List.length(&2, P.Para, ps)), 0)

# the counts of items added
def Cli.stat.items(its: List<&2, S.Item>, sts: List<&2, Stat>) -> List<&2, Stat>:
  match its:
    case Nil{}:
      sts
    case Con{it, rest}:
      match it:
        case S.Item{rec, from, upto}:
          Cli.stat.items(rest, Cli.stat.item(rec, from, upto, sts))

# one shard counted for each of its sources
def Cli.stat.sources(srcs: List<&2, String>, sts: List<&2, Stat>) -> List<&2, Stat>:
  match srcs:
    case Nil{}:
      sts
    case Con{src, rest}:
      Cli.stat.sources(rest, Cli.stat.put(sts, src, 0, 0, 1))

# the counts as lines, one per source
def Cli.stat.lines(sts: List<&2, Stat>) -> String:
  match sts:
    case Nil{}:
      ""
    case Con{st, rest}:
      match st:
        case Stat{source, records, paras, shards}:
          String.concat([source, " ", U32.show(records), " ", U32.show(paras),
            " ", U32.show(shards), "\n", Cli.stat.lines(rest)])

# the counts of shards added
def Cli.stat.shards(ss: List<&2, S.Shard>, sts: List<&2, Stat>) -> List<&2, Stat>:
  match ss:
    case Nil{}:
      sts
    case Con{sh, rest}:
      match sh:
        case S.Shard{_n, items, sources, _chars, _frozen}:
          Cli.stat.shards(rest, Cli.stat.sources(sources, Cli.stat.items(items, sts)))

# the first source of a shard's sources, "" when it has none
def Cli.stat.source(srcs: List<&2, String>) -> String:
  match srcs:
    case Nil{}:
      ""
    case Con{src, _rest}:
      src

# the counts of one light added: a shard that was read by its items, an
# unread one (a frozen shard of one source) by what its source's sizes file
# holds
def Cli.stat.light(sized: Maybe<&2, Nat>, +shard: S.Shard, recs: U32, sts: List<&2, Stat>) -> List<&2, Stat>:
  match sized:
    case None{}:
      Cli.stat.shards([shard], sts)
    case Some{paras}:
      match shard:
        case S.Shard{_n, _items, sources, _chars, _frozen}:
          Cli.stat.put(sts, Cli.stat.source(sources), recs, U32.from_nat(paras), 1)

# a wanted record id and paragraph number, if one was named
type Want is Data:
  Want{id: String, num: Maybe<&2, U32>}

# the id and number when the number read, else the whole argument
def Cli.want.num(got: Maybe<&2, U32>, id: String, arg: String) -> Want:
  match got:
    case Some{num}:
      Want{id, Some{num}}
    case None{}:
      Want{arg, None{}}

# the id and number of a cut at the last "#", when the number is one
def Cli.want.cut(got: Maybe<&2, Cut>, +arg: String) -> Want:
  match got:
    case None{}:
      Want{arg, None{}}
    case Some{Cut{id, num}}:
      Cli.want.num(U32.read(num), id, arg)

# the reversed pieces as the text before the last piece and the last piece
def Cli.cut.parts(rev: List<&2, String>, +sep: Char) -> Maybe<&2, Cut>:
  match rev:
    case Nil{}:
      None{}
    case Con{_last, Nil{}}:
      None{}
    case Con{last, Con{h, t}}:
      Some{Cut{String.join(List.reverse(&2, String, h <> t), String.from_list([sep])), last}}

# the text before the last sep and the text after it, or None
def Cli.cut.last(+str: String, +sep: Char) -> Maybe<&2, Cut>:
  Cli.cut.parts(List.reverse(&2, String, String.split(str, sep)), sep)

# `<id>` or `<id>#<n>` as a Want
def Cli.want(+arg: String) -> Want:
  Cli.want.cut(Cli.cut.last(arg, '#'), arg)

# rec when it is the one, else what comes after
def Cli.find.if(hit: Bool, rec: R.Record, after: Maybe<&2, R.Record>) -> Maybe<&2, R.Record>:
  match hit:
    case True{}:
      Some{rec}
    case False{}:
      after

# the record with the id, the first in log order, or None
def Cli.find(+id: String, recs: List<&2, R.Record>) -> Maybe<&2, R.Record>:
  match recs:
    case Nil{}:
      None{}
    case Con{+rec, rest}:
      match rec:
        case R.Record{rid, _ts, _source, _author, _thread, _parent, _paras, _ptr}:
          Cli.find.if(String.eq(id, rid), rec, Cli.find(id, rest))

# pa ahead of rest when it is the one
def Cli.numbered.if(hit: Bool, pa: P.Para, rest: List<&2, P.Para>) -> List<&2, P.Para>:
  match hit:
    case True{}:
      pa <> rest
    case False{}:
      rest

# the paragraphs numbered num
def Cli.numbered(+num: U32, ps: List<&2, P.Para>) -> List<&2, P.Para>:
  match ps:
    case Nil{}:
      []
    case Con{+pa, rest}:
      match pa:
        case P.Para{n, _start, _end, _text}:
          Cli.numbered.if(U32.is_eq(n, num), pa, Cli.numbered(num, rest))

# the paragraphs a Want names of a record: all, or the numbered one
def Cli.picked(num: Maybe<&2, U32>, ps: List<&2, P.Para>) -> List<&2, P.Para>:
  match num:
    case None{}:
      ps
    case Some{n}:
      Cli.numbered(n, ps)

# what a show writes: its output and what goes to stderr
type Shown is Data:
  Shown{out: String, err: String}

# a command's output, or its failure
def Cli.ran(res: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Shown:
  match res:
    case Fail{(_code, why)}:
      Shown{"", "episteme: " ++ why}
    case Done{(_code, (out, err))}:
      Shown{out, err}

# strings as JSON strings
def Cli.strs(xs: List<&2, String>) -> List<&2, Value.Json>:
  match xs:
    case Nil{}:
      []
    case Con{x, rest}:
      Json.str(x) <> Cli.strs(rest)

# a tool's input schema: an object of string properties, some required
def Cli.schema(props: List<&1, String & Value.Json>, req: List<&2, String>) -> Value.Json:
  Json.obj([("type", Json.str("object")), ("properties", Json.obj(props)),
    ("required", Json.arr(Cli.strs(req)))])

# a string property with its description
def Cli.prop(+name: String, desc: String) -> String & Value.Json:
  (name, Json.obj([("type", Json.str("string")), ("description", Json.str(desc))]))

# True when the subcommand was given
def Cli.given(got: Maybe<&2, Shake.Matched>) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{_m}:
      True{}

# the ingest command and its records input
def Cli.spec.ingest() -> Shake.Sub:
  Shake.sub("ingest", "Append new records to the log and pack them into shards; alone, pack log batches the shards lack.",
    [Shake.flag("reshard", None{}, Some{"reshard"},
      "Pack the whole log again at the configured shard size")],
    [Shake.sub("records", "Store records given as JSON lines, one record each as the log stores it; a changed record replaces its id's.",
      [Shake.flag("complete", None{}, Some{"complete"},
        "The input is the whole of each source it names: remove the records of those sources it lacks"),
       Shake.pos("input", "A file of JSON lines, or - for standard input", True{}, None{}, [])],
      [])])

# the commands episteme takes
def Cli.spec() -> Shake.Cli:
  Shake.app("episteme", "Primary-source Q&A over raw records.", Some{Cli.version()}, [],
    [Cli.spec.ingest(),
     Shake.sub("sources", "List each source with its records, paragraphs and shards.", [], []),
     Shake.sub("show", "Print a record, or one paragraph of it.",
       [Shake.pos("id", "<record id> or <record id>#<n>", True{}, None{}, [])], []),
     Shake.sub("serve", "Serve ask, show and sources as MCP tools over streamable HTTP at /mcp.",
       [Shake.opt("host", None{}, Some{"host"}, "The address to bind", False{}, Some{"127.0.0.1"}, []),
        Shake.opt("port", None{}, Some{"port"}, "The port to bind", False{}, Some{"18113"}, [])], []),
     Shake.sub("ask", "Read every shard the filter hits for a question; print verbatim excerpts.",
       [Shake.many("filter", None{}, Some{"filter"},
         "Sources to read: values and prefixes ending in /, comma-separated", False{}, None{}, []),
        Shake.opt("since", None{}, Some{"since"},
          "Read only records at or after this UTC date or time: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ",
          False{}, None{}, []),
        Shake.opt("author", None{}, Some{"author"},
          "Print only excerpts by these authors, comma-separated: for what one speaker said",
          False{}, None{}, []),
        Shake.flag("json", None{}, Some{"json"}, "Print one JSON object of excerpts and reads"),
        Shake.pos("question", "The question", True{}, None{}, [])], []),
     Shake.sub("eval-import", "Print a canon gold question set as questions.jsonl lines.",
       [Shake.pos("dir", "The canon corpus data directory, holding index.sqlite and text/",
         True{}, None{}, []),
        Shake.pos("questions", "The questions.yaml", True{}, None{}, []),
        Shake.pos("corpus", "The corpus name the books were ingested under", True{}, None{}, [])],
       []),
     Shake.sub("eval", "Run every question through ask and score recall of its gold spans.",
       [Shake.opt("label", None{}, Some{"label"}, "The run's name in runs/eval-<label>-<time>",
         True{}, None{}, []),
        Shake.pos("questions", "The questions.jsonl", True{}, None{}, [])], [])])
