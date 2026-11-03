# `Honcho.record(Msg{id, ts, peer, ws, session, body})` is
# `Record.make("honcho:" ++ id, ts, "chat:honcho", peer, ws ++ "/" ++ session,
# "", body, "")`, and every record of `Honcho.records(ms)` has source
# `chat:honcho`, no parent and no pointer.
#
# `src/honcho.bend` decides what a Honcho message becomes and how a session's
# messages are read. `Honcho.msg(js)` reads a message object as `Msg{id, ts,
# peer, ws, session, body}` from its `id`, `created_at`, `peer_id`,
# `workspace_id` and `session_id`, each a non-empty string, and its `content`,
# a string; any other object is no message. `Honcho.record(m)` is
# `Record.make` of the id `honcho:<id>`, the ts, the source `chat:honcho`, the
# peer as author, `<workspace>/<session>` as thread, no parent, the content as
# body and no pointer, so a message whose content has no paragraph makes no
# record. A session's messages are read in pages of `Honcho.size()` (100), the
# one place the page size is set; `Honcho.query(d)` is `?page=<d +
# 1>&size=<size>`. The cursor counts, per session, the messages read: a
# session read past its first `n` starts at `Honcho.place(n)`, `Place{n /
# size, n mod size}` (`Nat.divmod`): page index `d` (Honcho's page `d + 1`)
# and the `skip` of that page's items read before. `Honcho.step(Place{d,
# skip}, items)` reads a page: `Step{fresh, next}`, `fresh` the items after
# the first `skip` (`Honcho.fresh`), `next` `Place{d + 1, 0}` when the page
# holds `size` items (`Honcho.full`) and None, the read's end, otherwise.
# Every item counts, a message or not, so counts are the server's.
# `Honcho.walk(fuel, all, p)` is that read run purely against a model of
# Honcho's list of a session: `all` its messages in order, page `d` the `size`
# items after the first `d * size` (`Honcho.page`, by `Honcho.from`), step
# after step from `p`, at most `fuel` pages. The cursor holds one
# `<n>\t<thread>` line per session (`Honcho.cursor`, which reads it as
# `Chat.cursor` does; `Chat.cursor.get`, `set` and `text` read, change and
# write it, a session it does not list counting 0). `Honcho.ids(items)` is the
# non-empty `id` of each item of a workspace or session list page. Closed
# examples check a page's message objects read to records (one with fields
# kept, one lacking `peer_id` and one with empty content giving none), a body
# that is not a page, the ids of a list page, places and queries of 0, 100 and
# 250, and a cursor of count lines read back; no guarantee rests on them.
import Base
import ../src/record.bend as R
import ../src/honcho.bend as H
import ./defs/ListMembership.bend as D1

# what a Honcho record carries: its source, parent and pointer
def hon.stamp(record: R.Record) -> String & String & String:
  match record:
    case R.Record{_id, _ts, source, _author, _thread, parent, _paras, ptr}:
      (source, parent, ptr)

# LAW: a message is the record of its id, ts, peer, workspace/session and
# content, from chat:honcho, with no parent and no pointer
law hon_record:
  for id: String
  for ts: String
  for peer: String
  for ws: String
  for session: String
  for body: String
  {H.Honcho.record(H.Msg{id, ts, peer, ws, session, body})
    == R.Record.make("honcho:" ++ id, ts, "chat:honcho", peer, ws ++ "/" ++ session,
      "", body, "") : Maybe<&2, R.Record>}

# LAW: every record of messages is from chat:honcho, with no parent and no
# pointer
law hon_stamp:
  for ms: List<&2, H.Msg>
  for r: R.Record
  for h: D1.Elem(R.Record, r, H.Honcho.records(ms))
  {hon.stamp(r) == ("chat:honcho", "", "") : String & String & String}
