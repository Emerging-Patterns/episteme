# A question may say how deep its run is sifted, and a reader that ranks the
# run then takes no more for it than that.
#
# A reader that ranks a run names more than a question prints: everything it
# took up to its own limit, with ranks, so that whoever asked can sift the
# rest in the run's files (laws/BestRankedArePrinted.bend,
# laws/NextBestAreInPages.bend). That depth is paid for by every question:
# `ask` reads from its file each shard whose read named a label, to write
# the files. A caller that will read only what is printed (a hook, a tool
# that fans one lookup out into several questions) can say so.
#
# `episteme ask --depth <tokens>` (the `ask` tool's `depth`, read as the flag
# is: laws/ToolQueryIsCliQuery.bend) says how many tokens of paragraphs the
# run may hold in all, printed and in its files; `config.json`'s optional
# `depth_tokens` says it for every question that does not.
# `Read.depth.arg(arg)` reads the flag's value: no depth when there is no
# flag; the number when the value is a whole number; else a refusal naming
# the value (exit 2, and no reader asked). `Read.deeper(flag, config)` is
# the run's depth: the flag's when it gave one, else the config's.
#
# `Read.announce(names, q, who, depth)` is the run notice. With no depth it
# is exactly `Read.notice(names, q, who)` (laws/RunNoticeNamesShards.bend):
# a question that says none is announced as before, and nothing of its run
# changes. With depth n it is that body with one more field after the
# others, `"depth": n`. A reader that ranks the run (deploy/f2) then takes
# paragraphs for it until n tokens instead of its own limit, so the run
# names less, `ask` reads fewer shards from their files and writes fewer
# files, and with a depth no greater than `budget_tokens` everything named
# is printed and no file is written. A reader that does not rank, or does
# not know the field, reads the run as before.
#
# Not proved here: that a reader keeps to the depth is the reader's;
# `tests/serve.sh` checks that the fixture reader is told it and that a run
# of depth 1 prints one paragraph and writes no file.
import Base
import ../src/read.bend as Rd
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value

# a shard's name as an object
def name_object(nm: Rd.Name) -> Value.Json:
  match nm:
    case Rd.Name{source, n}:
      Json.obj([("source", Json.str(source)), ("n", Json.num(U32.show(n)))])

# the names as objects, in order
def name_objects(names: List<&2, Rd.Name>) -> List<&2, Value.Json>:
  match names:
    case Nil{}:
      []
    case Con{nm, rest}:
      name_object(nm) <> name_objects(rest)

# authors as JSON strings, in order
def author_strings(who: List<&2, String>) -> List<&2, Value.Json>:
  match who:
    case Nil{}:
      []
    case Con{name, rest}:
      Json.str(name) <> author_strings(rest)

# the depth a flag's value says once it is read as a number, or the refusal
def said(got: Maybe<&2, U32>, text: String) -> Result<&2, &2, String, Maybe<&2, U32>>:
  match got:
    case None{}:
      Fail{"--depth takes a whole number of tokens, not " ++ text}
    case Some{n}:
      Done{Some{n}}

# LAW: a question that says no depth is announced exactly as before
law no_depth_announces_as_before:
  for names: List<&2, Rd.Name>
  for question: String
  for who: List<&2, String>
  {Rd.Read.announce(names, question, who, None{}) == Rd.Read.notice(names, question, who) : Value.Json}

# LAW: a depth is announced after the question and the shards
law depth_follows_the_shards:
  for names: List<&2, Rd.Name>
  for question: String
  for n: U32
  {Rd.Read.announce(names, question, [], Some{n})
    == Json.obj([("question", Json.str(question)), ("shards", Json.arr(name_objects(names))),
      ("depth", Json.num(U32.show(n)))]) : Value.Json}

# LAW: and after the authors, when the question names any
law depth_follows_the_authors:
  for names: List<&2, Rd.Name>
  for question: String
  for name: String
  for who: List<&2, String>
  for n: U32
  {Rd.Read.announce(names, question, name <> who, Some{n})
    == Json.obj([("question", Json.str(question)), ("shards", Json.arr(name_objects(names))),
      ("authors", Json.arr(Json.str(name) <> author_strings(who))),
      ("depth", Json.num(U32.show(n)))]) : Value.Json}

# LAW: the flag's depth is the run's, whatever the config says
law flag_sets_the_depth:
  for n: U32
  for config: Maybe<&2, U32>
  {Rd.Read.deeper(Some{n}, config) == Some{n} : Maybe<&2, U32>}

# LAW: with no flag the run's depth is the config's, none when it has none
law no_flag_leaves_the_configs:
  for config: Maybe<&2, U32>
  {Rd.Read.deeper(None{}, config) == config : Maybe<&2, U32>}

# LAW: a flag's value is a depth exactly when it is a whole number, and is
# refused by name otherwise
law depth_is_a_whole_number:
  for +text: String
  {Rd.Read.depth.arg(Some{text}) == said(U32.read(text), text) : Result<&2, &2, String, Maybe<&2, U32>>}
