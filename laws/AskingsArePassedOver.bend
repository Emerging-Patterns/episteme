# A store that records the sessions that question it comes to hold its own
# questions: the command that asked one, a script that lists it, a line that
# quotes it. Such a paragraph is an earlier asking of the question, not
# evidence on it, and it matches the question better than any answer does,
# so every time a question is asked again its answer would hold more
# askings and less of anything else. `ask` passes them over.
#
# The words of a text, `Echo.words(text)`, are its unbroken runs of the
# letters a to z, in either case, and the digits, in order, each in lower
# case: quotes, escapes and line ends around a quoted question do not count.
# A paragraph of words `pw` holds a question of words `q` when the question
# is long, `Echo.long(q)`: it has `Echo.least()` (8) words or more, and its
# words are in the paragraph's, all of them, in order and unbroken
# (`Echo.within(q, pw)`). A question under eight words is held by no
# paragraph: it can be a phrase, a heading or a sentence a text says for
# itself, and the paragraph that has it may be the answer; from eight on it
# is the question, quoted. `Echo.hit(q, sh, label)` says whether the
# paragraph a label names on the shard `sh` holds the question, its words
# being `Echo.said(sh, label)`, none for a label the shard does not have.
#
# `Echo.read(q, sh, rd)` is the read `rd` of the shard `sh` keeping, in
# order, exactly its labels whose paragraph does not hold the question,
# each with its rank, and is otherwise the same read. `Echo.reads(q, rs, ss)`
# does so to each read of `rs` with the shard in its place of `ss`: `ask`
# gives it one read per shard in the shards' order
# (laws/OrderedTakesFirstRead.bend). `ask` then ranks, prints and files the
# reads so passed (laws/BestRankedArePrinted.bend), so a
# paragraph that holds the question is not printed and is in no run file,
# and its place in the budget goes to the next ranked.
#
# Proved here: that the question's words, unbroken, are found wherever they
# stand in a paragraph's; that a question under `Echo.least()` words is held
# by no paragraph and changes no read; what a read keeps. Not proved: that
# `Echo.within` finds nothing else (its converse), and that `Echo.words`
# splits a text as said above, which the example law shows on one text.
import Base
import ../src/shard.bend as S
import ../src/read.bend as Rd
import ../src/echo.bend as Ec

# the labels of ls, in order, whose paragraph on the shard does not hold q
def kept(+q: List<&2, String>, +sh: S.Shard, ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{+l, rest}:
      List.filter.put(String, l, kept(q, sh, rest), Bool.not(Ec.Echo.hit(q, sh, l)))

# the ranks of rks, in order, of the labels kept keeps of ls: a rank goes
# with the label in its place, ranks past the labels' end are kept
def kept_ranks(
  +q: List<&2, String>,
  +sh: S.Shard,
  ls: List<&2, String>,
  rks: List<&2, U32>
) -> List<&2, U32>:
  match ls rks:
    case Nil{} rks:
      rks
    case Con{_l, _rest} Nil{}:
      []
    case Con{l, rest} Con{rk, more}:
      List.filter.put(U32, rk, kept_ranks(q, sh, rest, more), Bool.not(Ec.Echo.hit(q, sh, l)))

# LAW: the question's words, unbroken, are found wherever they stand in a
# paragraph's words
law run_is_found:
  for +q: List<&2, String>
  for pre: List<&2, String>
  for +post: List<&2, String>
  {Ec.Echo.within(q, List.append(&2, String, pre, List.append(&2, String, q, post)))
    == True{} : Bool}

# LAW: a question under Echo.least() words is held by no paragraph
law short_is_not_held:
  for +q: List<&2, String>
  for sh: S.Shard
  for label: String
  for short: {Ec.Echo.long(q) == False{} : Bool}
  {Ec.Echo.hit(q, sh, label) == False{} : Bool}

# LAW: a long question is held by exactly the paragraphs its words are
# within
law long_is_held_within:
  for +q: List<&2, String>
  for sh: S.Shard
  for label: String
  for long: {Ec.Echo.long(q) == True{} : Bool}
  {Ec.Echo.hit(q, sh, label) == Ec.Echo.within(q, Ec.Echo.said(sh, label)) : Bool}

# LAW: a read keeps exactly its labels whose paragraph does not hold the
# question, in order, each with its rank, and is otherwise the same read
law read_keeps_the_rest:
  for +q: List<&2, String>
  for +sh: S.Shard
  for shard: U32
  for inst: String
  for +labels: List<&2, String>
  for ranks: List<&2, U32>
  for ok: Bool
  for why: String
  for pn: U32
  for pm: U32
  for cn: U32
  for ms: U32
  {Ec.Echo.read(q, sh, Rd.Read{shard, inst, labels, ranks, ok, why, pn, pm, cn, ms})
    == Rd.Read{shard, inst, kept(q, sh, labels), kept_ranks(q, sh, labels, ranks),
      ok, why, pn, pm, cn, ms} : Rd.Read}

# LAW: a question under Echo.least() words changes no read
law short_changes_no_read:
  for +q: List<&2, String>
  for rs: List<&2, Rd.Read>
  for ss: List<&2, S.Shard>
  for short: {Ec.Echo.long(q) == False{} : Bool}
  {Ec.Echo.reads(q, rs, ss) == rs : List<&2, Rd.Read>}

# LAW: a command that asked a question holds it, whatever stands after it:
# the words are split at every sign and space and put in lower case
law asking_holds_example:
  for +post: List<&2, String>
  {Ec.Echo.within(Ec.Echo.words("Why did we move the reader to GPU 1?"),
    List.append(&2, String,
      Ec.Echo.words("Bash\n{\"command\":\"episteme ask \\\"why did we MOVE the reader to gpu-1?\\\" | tail\"}"),
      post))
    == True{} : Bool}

# LAW: the words of a text are its runs of letters and digits, lower case
law words_example:
  for +tail: List<&2, String>
  {List.append(&2, String, Ec.Echo.words("ask \\\"Why GPU-1?\\\"\n2 a.m."), tail)
    == "ask" <> "why" <> "gpu" <> "1" <> "2" <> "a" <> "m" <> tail : List<&2, String>}
