# A reader that ranked a run may tell the run's reads in its answer to the
# notice, one for each shard the notice named, and `ask` then takes those
# and asks it for no shard.
#
# A reader that ranks a whole run (laws/RunNoticeNamesShards.bend) has every
# shard's answer when it answers the notice. Asked for each by name
# (laws/RankedReadNamesShard.bend) it only hands them over, one request a
# shard: seven hundred requests for a run of seven hundred shards, each
# naming nothing or a few labels. Its answer to the notice may hold them all:
# beside `"ranked": true`, `"reads": [c1, c2, ...]`, an array of strings, ck
# what the read of the run's k-th shard would hold as its reply's content,
# `{"ids": [...], "ranks": [...]}`.
#
# `Read.told(status, text, names, inst)` is the reads the answer tells, by
# its status and body, for the run's shards named `names`, read on the
# instance `inst`:
#
# - None unless the answer says the run was ranked (`Read.ranked`), so an
#   answer that tells reads without ranking the run tells nothing;
# - None unless its JSON holds `reads`, an array of strings only;
# - None unless there are exactly as many strings as names: a reader that
#   tells reads for some shards has told none, and every shard is then read
#   by name as before, so no shard is left unread and none is read twice;
# - else Some of exactly one read for each name, in order, the k-th numbered
#   k from 1 as the run's shards are, and `Read.said(k, inst, ck)`: the read
#   a 200 reply with content ck gives (the ids its `ids` names, the ranks
#   its `ranks` gives them, no timings), which is ok exactly when ck is JSON
#   whose `ids` is an array of strings, and a failed read otherwise.
#
# A told read's labels are resolved against its own shard like any other
# (laws/ResolveKeepsNamedParagraphs.bend), so a label still names a paragraph
# of the shard it was read for. `Read.first(told)` is what a run takes of
# several instances' answers: the reads of the first that told them, in pool
# order, and None when none did.
#
# Not proved here: that `ask` posts no read when `Read.first` gives reads is
# src/ask.bend's sequencing (trusted there); `tests/serve.sh` checks it with
# a reader that tells its reads and answers no read.
import Base
import ../src/read.bend as Rd
import ./defs/ReadOk.bend as D1
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value

# a read ahead of the reads told after it, or None when those are not told
def ahead(rd: Rd.Read, more: Maybe<&2, List<&2, Rd.Read>>) -> Maybe<&2, List<&2, Rd.Read>>:
  match more:
    case None{}:
      None{}
    case Some{rs}:
      Some{rd <> rs}

# the reads told for names by contents, numbered from num: one a name, in
# order, and None when there are more or fewer contents than names
def tells(
  names: List<&2, Rd.Name>,
  contents: List<&2, String>,
  +inst: String,
  +num: U32
) -> Maybe<&2, List<&2, Rd.Read>>:
  match names contents:
    case Nil{} Nil{}:
      Some{[]}
    case Con{_nm, rest} Con{content, more}:
      ahead(Rd.Read.said(num, inst, content), tells(rest, more, inst, U32.inc(num)))
    case Nil{} Con{_content, _more}:
      None{}
    case Con{_nm, _rest} Nil{}:
      None{}

# whether two lists are as long as each other
def as_many(names: List<&2, Rd.Name>, contents: List<&2, String>) -> Bool:
  match names contents:
    case Nil{} Nil{}:
      True{}
    case Con{_nm, rest} Con{_content, more}:
      as_many(rest, more)
    case Nil{} Con{_content, _more}:
      False{}
    case Con{_nm, _rest} Nil{}:
      False{}

# how many reads are told, or want when none are
def told_or(got: Maybe<&2, List<&2, Rd.Read>>, want: Nat) -> Nat:
  match got:
    case None{}:
      want
    case Some{rs}:
      List.length(&2, Rd.Read, rs)

# the strings a parsed answer holds as reads, or None
def says_reads(got: Maybe<&2, Value.Json>) -> Maybe<&2, List<&2, String>>:
  match got:
    case None{}:
      None{}
    case Some{js}:
      Rd.Read.arr(Json.get(js, "reads"))

# the reads those strings tell for names, or None
def told_by(
  contents: Maybe<&2, List<&2, String>>,
  names: List<&2, Rd.Name>,
  +inst: String
) -> Maybe<&2, List<&2, Rd.Read>>:
  match contents:
    case None{}:
      None{}
    case Some{cs}:
      tells(names, cs, inst, 1)

# what an answer tells by whether it says the run was ranked
def told_if(
  ranked: Bool,
  text: String,
  names: List<&2, Rd.Name>,
  +inst: String
) -> Maybe<&2, List<&2, Rd.Read>>:
  match ranked:
    case False{}:
      None{}
    case True{}:
      told_by(says_reads(Json.parse(text)), names, inst)

# the first reads told, or None
def first_told(told: List<&2, Maybe<&2, List<&2, Rd.Read>>>) -> Maybe<&2, List<&2, Rd.Read>>:
  match told:
    case Nil{}:
      None{}
    case Con{got, rest}:
      match got:
        case Some{rs}:
          Some{rs}
        case None{}:
          first_told(rest)

# LAW: an answer tells reads exactly as the specification says: only when it
# says the run was ranked and holds one string a name
law told_is_ranked_and_whole:
  for +status: U32
  for +text: String
  for names: List<&2, Rd.Name>
  for +inst: String
  {Rd.Read.told(status, text, names, inst)
    == told_if(Rd.Read.ranked(status, text), text, names, inst)
    : Maybe<&2, List<&2, Rd.Read>>}

# LAW: reads are told exactly when there are as many contents as names:
# never for some of the shards
law tells_all_or_none:
  for names: List<&2, Rd.Name>
  for contents: List<&2, String>
  for +inst: String
  for +num: U32
  {Maybe.is_some(&2, List<&2, Rd.Read>, Rd.Read.tell(names, contents, inst, num))
    == as_many(names, contents) : Bool}

# LAW: when reads are told there is exactly one for each name
law tells_one_read_a_name:
  for names: List<&2, Rd.Name>
  for contents: List<&2, String>
  for +inst: String
  for +num: U32
  {told_or(Rd.Read.tell(names, contents, inst, num), List.length(&2, Rd.Name, names))
    == List.length(&2, Rd.Name, names) : Nat}

# LAW: the reads told are each name's own, in order, numbered as the run's
# shards are
law tells_in_order:
  for names: List<&2, Rd.Name>
  for contents: List<&2, String>
  for +inst: String
  for +num: U32
  {Rd.Read.tell(names, contents, inst, num) == tells(names, contents, inst, num)
    : Maybe<&2, List<&2, Rd.Read>>}

# LAW: a told read is ok exactly when its content is JSON whose ids is an
# array of strings; a content that is not is a failed read, never an empty
# answer
law said_is_ok_with_ids:
  for shard: U32
  for inst: String
  for +content: String
  {D1.read.ok(Rd.Read.said(shard, inst, content))
    == Maybe.is_some(&2, List<&2, String>, Rd.Read.answer(Some{content})) : Bool}

# LAW: a run takes the reads of the first instance that told them
law first_is_first_told:
  for told: List<&2, Maybe<&2, List<&2, Rd.Read>>>
  {Rd.Read.first(told) == first_told(told) : Maybe<&2, List<&2, Rd.Read>>}
