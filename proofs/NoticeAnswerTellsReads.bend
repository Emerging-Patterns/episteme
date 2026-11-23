# proofs of laws/NoticeAnswerTellsReads.bend
import Base
import ../src/read.bend as Rd
import ../laws/defs/ReadOk.bend as D1
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value
import ../laws/NoticeAnswerTellsReads.bend as Laws

# a read put ahead of told reads is the specification's
law cons_eq:
  for rd: Rd.Read
  for more: Maybe<&2, List<&2, Rd.Read>>
  {Rd.Read.tell.cons(rd, more) == Laws.ahead(rd, more) : Maybe<&2, List<&2, Rd.Read>>}

def cons_eq(_rd, more):
  match more:
    case None{}:
      {==}
    case Some{_rs}:
      {==}

def Laws.tells_in_order(names, contents, inst, num):
  match names contents:
    case Nil{} Nil{}:
      {==}
    case Con{_nm, +rest} Con{+content, +more}:
      Equal.trans(Maybe<&2, List<&2, Rd.Read>>,
        Rd.Read.tell.cons(Rd.Read.said(num, inst, content), Rd.Read.tell(rest, more, inst, U32.inc(num))),
        Rd.Read.tell.cons(Rd.Read.said(num, inst, content), Laws.tells(rest, more, inst, U32.inc(num))),
        Laws.ahead(Rd.Read.said(num, inst, content), Laws.tells(rest, more, inst, U32.inc(num))),
        Equal.cong(Maybe<&2, List<&2, Rd.Read>>, Maybe<&2, List<&2, Rd.Read>>,
          z => Rd.Read.tell.cons(Rd.Read.said(num, inst, content), z),
          Rd.Read.tell(rest, more, inst, U32.inc(num)), Laws.tells(rest, more, inst, U32.inc(num)),
          Laws.tells_in_order(rest, more, inst, U32.inc(num))),
        cons_eq(Rd.Read.said(num, inst, content), Laws.tells(rest, more, inst, U32.inc(num))))
    case Nil{} Con{_content, _more}:
      {==}
    case Con{_nm, _rest} Nil{}:
      {==}

# a read ahead of told reads is told exactly when they are
law ahead_some:
  for rd: Rd.Read
  for more: Maybe<&2, List<&2, Rd.Read>>
  {Maybe.is_some(&2, List<&2, Rd.Read>, Rd.Read.tell.cons(rd, more))
    == Maybe.is_some(&2, List<&2, Rd.Read>, more) : Bool}

def ahead_some(_rd, more):
  match more:
    case None{}:
      {==}
    case Some{_rs}:
      {==}

def Laws.tells_all_or_none(names, contents, inst, num):
  match names contents:
    case Nil{} Nil{}:
      {==}
    case Con{_nm, +rest} Con{+content, +more}:
      Equal.trans(Bool,
        Maybe.is_some(&2, List<&2, Rd.Read>,
          Rd.Read.tell.cons(Rd.Read.said(num, inst, content), Rd.Read.tell(rest, more, inst, U32.inc(num)))),
        Maybe.is_some(&2, List<&2, Rd.Read>, Rd.Read.tell(rest, more, inst, U32.inc(num))),
        Laws.as_many(rest, more),
        ahead_some(Rd.Read.said(num, inst, content), Rd.Read.tell(rest, more, inst, U32.inc(num))),
        Laws.tells_all_or_none(rest, more, inst, U32.inc(num)))
    case Nil{} Con{_content, _more}:
      {==}
    case Con{_nm, _rest} Nil{}:
      {==}

# a read ahead of told reads makes one more of them, and of none, none
law ahead_count:
  for rd: Rd.Read
  for more: Maybe<&2, List<&2, Rd.Read>>
  for want: Nat
  {Laws.told_or(Rd.Read.tell.cons(rd, more), 1n+want) == 1n+Laws.told_or(more, want) : Nat}

def ahead_count(_rd, more, _want):
  match more:
    case None{}:
      {==}
    case Some{_rs}:
      {==}

def Laws.tells_one_read_a_name(names, contents, inst, num):
  match names contents:
    case Nil{} Nil{}:
      {==}
    case Con{_nm, +rest} Con{+content, +more}:
      Equal.trans(Nat,
        Laws.told_or(Rd.Read.tell.cons(Rd.Read.said(num, inst, content), Rd.Read.tell(rest, more, inst, U32.inc(num))),
          1n+List.length(&2, Rd.Name, rest)),
        1n+Laws.told_or(Rd.Read.tell(rest, more, inst, U32.inc(num)), List.length(&2, Rd.Name, rest)),
        1n+List.length(&2, Rd.Name, rest),
        ahead_count(Rd.Read.said(num, inst, content), Rd.Read.tell(rest, more, inst, U32.inc(num)),
          List.length(&2, Rd.Name, rest)),
        Equal.cong(Nat, Nat, x => 1n+x,
          Laws.told_or(Rd.Read.tell(rest, more, inst, U32.inc(num)), List.length(&2, Rd.Name, rest)),
          List.length(&2, Rd.Name, rest),
          Laws.tells_one_read_a_name(rest, more, inst, U32.inc(num))))
    case Nil{} Con{_content, _more}:
      {==}
    case Con{_nm, _rest} Nil{}:
      {==}

# a parsed answer holds reads as the specification says
law of_eq:
  for got: Maybe<&2, Value.Json>
  {Rd.Read.told.of(got) == Laws.says_reads(got) : Maybe<&2, List<&2, String>>}

def of_eq(got):
  match got:
    case None{}:
      {==}
    case Some{_js}:
      {==}

# the strings tell reads as the specification says
law by_eq:
  for contents: Maybe<&2, List<&2, String>>
  for names: List<&2, Rd.Name>
  for +inst: String
  {Rd.Read.told.by(contents, names, inst) == Laws.told_by(contents, names, inst) : Maybe<&2, List<&2, Rd.Read>>}

def by_eq(contents, names, inst):
  match contents:
    case None{}:
      {==}
    case Some{cs}:
      Laws.tells_in_order(names, cs, inst, 1)

# what a parsed answer holds tells reads as the specification says
law by_of:
  for got: Maybe<&2, Value.Json>
  for names: List<&2, Rd.Name>
  for +inst: String
  {Rd.Read.told.by(Rd.Read.told.of(got), names, inst) == Laws.told_by(Laws.says_reads(got), names, inst)
    : Maybe<&2, List<&2, Rd.Read>>}

def by_of(got, names, inst):
  match got:
    case None{}:
      {==}
    case Some{js}:
      by_eq(Rd.Read.arr(Json.get(js, "reads")), names, inst)

# ranked or not, an answer tells reads as the specification says
law if_eq:
  for ranked: Bool
  for text: String
  for names: List<&2, Rd.Name>
  for +inst: String
  {Rd.Read.told.if(ranked, text, names, inst) == Laws.told_if(ranked, text, names, inst)
    : Maybe<&2, List<&2, Rd.Read>>}

def if_eq(ranked, text, names, inst):
  match ranked:
    case False{}:
      {==}
    case True{}:
      by_of(Json.parse(text), names, inst)

def Laws.told_is_ranked_and_whole(status, text, names, inst):
  if_eq(Rd.Read.ranked(status, text), text, names, inst)

# a 200 reply's read is ok exactly when it has ids, whatever ranks it is given
law got_ok:
  for ids: Maybe<&2, List<&2, String>>
  for shard: U32
  for inst: String
  for +tm: Value.Json
  for text: String
  for ranks: List<&2, U32>
  {D1.read.ok(Rd.Read.rated(Rd.Read.got(ids, shard, inst, tm, text), ranks))
    == Maybe.is_some(&2, List<&2, String>, ids) : Bool}

def got_ok(ids, _shard, _inst, _tm, _text, _ranks):
  match ids:
    case None{}:
      {==}
    case Some{_ls}:
      {==}

def Laws.said_is_ok_with_ids(shard, inst, content):
  got_ok(Rd.Read.answer(Some{content}), shard, inst, Json.null(), content, Rd.Read.ranks(Some{content}))

def Laws.first_is_first_told(told):
  match told:
    case Nil{}:
      {==}
    case Con{got, rest}:
      match got:
        case Some{rs}:
          {==}
        case None{}:
          Laws.first_is_first_told(rest)
