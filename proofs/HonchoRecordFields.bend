# proofs of laws/HonchoRecordFields.bend
import Base
import ../src/para.bend as P
import ../src/record.bend as R
import ../src/chat.bend as C
import ../src/honcho.bend as H
import ../laws/HonchoRecordFields.bend as Laws
import ../laws/defs/ListMembership.bend as D1
import ./lemmas/OrElse.bend as M1

def Laws.hon_record(_id, _ts, _peer, _ws, _session, _body):
  {==}

# a record of a made record ahead of rest is the made one, from chat:honcho
# with no parent and no pointer, or one of rest
def hon_made(
  -id: String,
  -ts: String,
  -author: String,
  -thread: String,
  ps: List<&2, P.Para>,
  -r: R.Record,
  -rest: List<&2, R.Record>,
  h: D1.Elem(R.Record, r, C.Chat.put(R.Record.make.go(id, ts, "chat:honcho", author, thread, "", ps, ""), rest))
) -> Or({Laws.hon.stamp(r) == ("chat:honcho", "", "") : String & String & String},
  D1.Elem(R.Record, r, rest)):
  match ps:
    case Nil{}:
      Inr{h}
    case Con{p, more}:
      match h:
        case Inl{e}:
          Inl{%Equal.sym(R.Record, r,
              R.Record{id, ts, "chat:honcho", author, thread, "", p <> more, ""}, e)
            : {Laws.hon.stamp(_) == ("chat:honcho", "", "") : String & String & String}
            {==}}
        case Inr{hr}:
          Inr{hr}

# every record of messages is from chat:honcho, with no parent and no pointer
def hon_stamp(
  ms: List<&2, H.Msg>,
  -r: R.Record,
  h: D1.Elem(R.Record, r, H.Honcho.records(ms))
) -> {Laws.hon.stamp(r) == ("chat:honcho", "", "") : String & String & String}:
  match ms:
    case Nil{}:
      Empty.absurd({Laws.hon.stamp(r) == ("chat:honcho", "", "") : String & String & String}, h)
    case Con{m, rest}:
      match m:
        case H.Msg{id, ts, peer, ws, session, body}:
          M1.or_else({Laws.hon.stamp(r) == ("chat:honcho", "", "") : String & String & String},
            D1.Elem(R.Record, r, H.Honcho.records(rest)),
            hon_made("honcho:" ++ id, ts, peer, ws ++ "/" ++ session,
              P.Para.split(body), r, H.Honcho.records(rest), h),
            hr => hon_stamp(rest, r, hr))

def Laws.hon_stamp(ms, r, h):
  hon_stamp(ms, r, h)
