# episteme/src/reader: one call to a reader instance, llama-server's
# chat completions on one of its slots, and its health check. IO: the
# trusted shell around Read.request and Read.reply.
#
# Trusted, not proved: `Reader.call(url, Read.Call{path, body}, k)` POSTs
# body to `<url><path>` with ezhttp's `http.post_opts`, a 600000 ms timeout,
# and answers `Read.reply` of the status and body for the run's shard k, or
# a failed read naming the transport error (`Client.Err`).
# `Reader.health(url)` GETs `<url>/health` with a 10000 ms timeout; any answer
# but a 200 is a reason.
#
# Trusted, not proved: `Reader.notice(url, body)` POSTs body (a
# `Read.notice`) to `<url>/v1/episteme/run` with a 3600000 ms timeout and
# answers `Read.ranked` of the status and body, and False on a transport
# error: a reader that ranks a run may first read its cold shards, and one
# without the endpoint answers 404.
#
# Why it is trusted: It is HTTP through ezhttp's client, which no law reaches;
# ezhttp's own gate trusts its wire effect (on its src/client.bend and
# src/wire.bend). What a reply means is laws/ReplyIsOkOrFailed.bend.
# `tests/live.sh` runs it against llama-server.
import Base
import ./shard.bend as S
import ./read.bend as Rd
import 0x7367809738fddd234b8d2bed772ad2cf/main.bend as Ez
import 0x7367809738fddd234b8d2bed772ad2cf/src/http.bend as Http
import 0x7367809738fddd234b8d2bed772ad2cf/src/client.bend as Client
import 0xa81e161008ecc2f297c0a3065cb9b188/main.bend as Json
import 0xa81e161008ecc2f297c0a3065cb9b188/src/value.bend as Value

# how long one call may take, in milliseconds
def Reader.timeout() -> U32:
  600000

# the read of a response: a transport error is a failed read
def Reader.took(res: Client.Response, shard: U32, inst: String) -> Rd.Read:
  match res:
    case Client.Err{why}:
      Rd.Read.fail(shard, inst, why)
    case Client.Response{status, _headers, _reason, bytes}:
      Rd.Read.reply(shard, inst, status, Ez.body_text(bytes))

# make a read's call (Read.call) on the instance at url: which paragraphs of
# the run's shard numbered shard bear on the question
def Reader.call(+url: String, call: Rd.Call, +shard: U32) -> IO(Rd.Read):
  match call:
    case Rd.Call{path, body}:
      do IO<Rd.Read>:
        res : Client.Response <- Ez.http.post_opts(url ++ path,
          [Http.H{"Content-Type", "application/json"}],
          Ez.text_body(Json.print(body)), Reader.timeout())
        return Reader.took(res, shard, url)

# None when a health response is 200, else why not
def Reader.healthy(res: Client.Response) -> Maybe<&2, String>:
  match res:
    case Client.Err{why}:
      Some{why}
    case Client.Response{+status, _headers, _reason, bytes}:
      Bool.pick(Maybe<&2, String>, U32.is_eq(status, 200), None{},
        Some{"HTTP " ++ U32.show(status) ++ ": " ++ Rd.Read.clip(Ez.body_text(bytes))})

# None when the instance at url answers /health with 200 within 10 s,
# else why not
def Reader.health(url: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    res : Client.Response <- Ez.http.get_opts(url ++ "/health", [], 10000, False{})
    return Reader.healthy(res)

# how long a run notice may take, in milliseconds: a ranking reader reads
# the run's cold shards before it answers
def Reader.notice_timeout() -> U32:
  3600000

# whether a notice's response says the instance ranked the run
# (Read.ranked); a transport error says it did not
def Reader.ranked(res: Client.Response) -> Bool:
  match res:
    case Client.Err{_why}:
      False{}
    case Client.Response{status, _headers, _reason, bytes}:
      Rd.Read.ranked(status, Ez.body_text(bytes))

# tell the instance at url which shards a run reads; answers whether it
# ranked the run, so its reads can name their shards
def Reader.notice(+url: String, +body: Value.Json) -> IO(Bool):
  do IO<Bool>:
    res : Client.Response <- Ez.http.post_opts(url ++ "/v1/episteme/run",
      [Http.H{"Content-Type", "application/json"}],
      Ez.text_body(Json.print(body)), Reader.notice_timeout())
    return Reader.ranked(res)
