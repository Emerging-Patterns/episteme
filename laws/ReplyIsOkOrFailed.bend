# `Read.reply(n, inst, status, text)` is ok exactly when status is 200, `text`
# is JSON and `Read.answer(Read.content(...))` of it is an ids array of
# strings, and then its labels are those ids; otherwise it is failed with no
# labels, never an empty answer. The labels resolved on a shard are its read's
# labels when the read is ok, and none when it failed.
import Base
import ../src/read.bend as Rd
import ezjson@1.2.0.0/main.bend as Json
import ezjson@1.2.0.0/src/value.bend as Value
import ./defs/ReadOk.bend as D1

# a read's labels
def read.labels(rd: Rd.Read) -> List<&2, String>:
  match rd:
    case Rd.Read{_shard, _inst, labels, _ok, _why, _pn, _pm, _cn, _ms}:
      labels

# the ids a parsed reply body names: its first choice's content read as
# the answer {"ids": [...]}, or None
def body_ids(got: Maybe<&2, Value.Json>) -> Maybe<&2, List<&2, String>>:
  match got:
    case None{}:
      None{}
    case Some{js}:
      Rd.Read.answer(Rd.Read.content(js))

# the ids a reply names: for a 200, those its body names; for any other
# status, none
def answered(ok: Bool, text: String) -> Maybe<&2, List<&2, String>>:
  match ok:
    case True{}:
      body_ids(Json.parse(text))
    case False{}:
      None{}

# LAW: a read is ok exactly when its reply is a 200 whose body names an
# ids array of strings; a failed call is never an empty answer
law reply_ok:
  for shard: U32
  for inst: String
  for +status: U32
  for +text: String
  {D1.read.ok(Rd.Read.reply(shard, inst, status, text))
    == Maybe.is_some(&2, List<&2, String>, answered(U32.is_eq(status, 200), text))
    : Bool}

# LAW: a read's labels are the ids its reply names, and none when it failed
law reply_labels:
  for shard: U32
  for inst: String
  for +status: U32
  for +text: String
  {read.labels(Rd.Read.reply(shard, inst, status, text))
    == Maybe.default(&2, List<&2, String>, answered(U32.is_eq(status, 200), text), [])
    : List<&2, String>}

# LAW: a shard's labels to resolve are its read's labels when the read is
# ok, and none when it failed
law labels_ok:
  for r: Rd.Read
  {Rd.Read.labels(Some{r})
    == Bool.pick(List<&2, String>, D1.read.ok(r), read.labels(r), [])
    : List<&2, String>}
