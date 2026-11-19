# proofs of laws/ReplyIsOkOrFailed.bend
import Base
import ../src/read.bend as Rd
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value
import ../laws/ReplyIsOkOrFailed.bend as Laws
import ../laws/defs/ReadOk.bend as D1

# a read of a 200's ids is ok exactly when there are ids
law got_ok:
  for ids: Maybe<&2, List<&2, String>>
  for shard: U32
  for inst: String
  for tm: Value.Json
  for text: String
  {D1.read.ok(Rd.Read.got(ids, shard, inst, tm, text))
    == Maybe.is_some(&2, List<&2, String>, ids) : Bool}

def got_ok(ids, _shard, _inst, _tm, _text):
  match ids:
    case None{}:
      {==}
    case Some{_ls}:
      {==}

# a read of a 200's ids has them as its labels, or none
law got_labels:
  for ids: Maybe<&2, List<&2, String>>
  for shard: U32
  for inst: String
  for tm: Value.Json
  for text: String
  {Laws.read.labels(Rd.Read.got(ids, shard, inst, tm, text))
    == Maybe.default(&2, List<&2, String>, ids, []) : List<&2, String>}

def got_labels(ids, _shard, _inst, _tm, _text):
  match ids:
    case None{}:
      {==}
    case Some{_ls}:
      {==}

# a read with its ranks is ok when the read is
law rated_ok:
  for rd: Rd.Read
  for ranks: List<&2, U32>
  {D1.read.ok(Rd.Read.rated(rd, ranks)) == D1.read.ok(rd) : Bool}

def rated_ok(rd, _ranks):
  match rd:
    case Rd.Read{_shard, _inst, _labels, _old, _ok, _why, _pn, _pm, _cn, _ms}:
      {==}

# a read with its ranks has the read's labels
law rated_labels:
  for rd: Rd.Read
  for ranks: List<&2, U32>
  {Laws.read.labels(Rd.Read.rated(rd, ranks)) == Laws.read.labels(rd) : List<&2, String>}

def rated_labels(rd, _ranks):
  match rd:
    case Rd.Read{_shard, _inst, _labels, _old, _ok, _why, _pn, _pm, _cn, _ms}:
      {==}

# a read of a parsed body is ok exactly when the body names ids
law parsed_ok:
  for got: Maybe<&2, Value.Json>
  for +shard: U32
  for +inst: String
  for +text: String
  {D1.read.ok(Rd.Read.parsed(got, shard, inst, text))
    == Maybe.is_some(&2, List<&2, String>, Laws.body_ids(got)) : Bool}

def parsed_ok(got, shard, inst, text):
  match got:
    case None{}:
      {==}
    case Some{+js}:
      %Equal.sym(Bool,
        D1.read.ok(Rd.Read.rated(
          Rd.Read.got(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text),
          Rd.Read.ranks(Rd.Read.content(js)))),
        D1.read.ok(Rd.Read.got(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text)),
        rated_ok(Rd.Read.got(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text),
          Rd.Read.ranks(Rd.Read.content(js))))
        : {_ == Maybe.is_some(&2, List<&2, String>, Rd.Read.answer(Rd.Read.content(js))) : Bool}
      got_ok(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text)

# a read of a parsed body has the ids it names as its labels, or none
law parsed_labels:
  for got: Maybe<&2, Value.Json>
  for +shard: U32
  for +inst: String
  for +text: String
  {Laws.read.labels(Rd.Read.parsed(got, shard, inst, text))
    == Maybe.default(&2, List<&2, String>, Laws.body_ids(got), []) : List<&2, String>}

def parsed_labels(got, shard, inst, text):
  match got:
    case None{}:
      {==}
    case Some{+js}:
      %Equal.sym(List<&2, String>,
        Laws.read.labels(Rd.Read.rated(
          Rd.Read.got(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text),
          Rd.Read.ranks(Rd.Read.content(js)))),
        Laws.read.labels(Rd.Read.got(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text)),
        rated_labels(Rd.Read.got(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text),
          Rd.Read.ranks(Rd.Read.content(js))))
        : {_ == Maybe.default(&2, List<&2, String>, Rd.Read.answer(Rd.Read.content(js)), []) : List<&2, String>}
      got_labels(Rd.Read.answer(Rd.Read.content(js)), shard, inst, Json.get(js, "timings"), text)

# a reply by its status test is ok exactly when it names ids
law reply_if_ok:
  for b: Bool
  for shard: U32
  for inst: String
  for status: U32
  for +text: String
  {D1.read.ok(Rd.Read.reply.if(b, shard, inst, status, text))
    == Maybe.is_some(&2, List<&2, String>, Laws.answered(b, text)) : Bool}

def reply_if_ok(b, shard, inst, _status, text):
  match b:
    case True{}:
      parsed_ok(Json.parse(text), shard, inst, text)
    case False{}:
      {==}

# a reply by its status test has the ids it names as its labels, or none
law reply_if_labels:
  for b: Bool
  for shard: U32
  for inst: String
  for status: U32
  for +text: String
  {Laws.read.labels(Rd.Read.reply.if(b, shard, inst, status, text))
    == Maybe.default(&2, List<&2, String>, Laws.answered(b, text), [])
    : List<&2, String>}

def reply_if_labels(b, shard, inst, _status, text):
  match b:
    case True{}:
      parsed_labels(Json.parse(text), shard, inst, text)
    case False{}:
      {==}

def Laws.reply_ok(shard, inst, status, text):
  reply_if_ok(U32.is_eq(status, 200), shard, inst, status, text)

def Laws.reply_labels(shard, inst, status, text):
  reply_if_labels(U32.is_eq(status, 200), shard, inst, status, text)

def Laws.labels_ok(r):
  match r:
    case Rd.Read{_shard, _inst, _labels, _ranks, _ok, _why, _pn, _pm, _cn, _ms}:
      {==}
