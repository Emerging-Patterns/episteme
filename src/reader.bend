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
# Trusted, not proved: `Reader.notice(url, body, names)` POSTs body (a
# `Read.notice` of names) to `<url>/v1/episteme/run` with a 3600000 ms
# timeout and answers `Heard` of `Read.ranked` and `Read.told` of the status
# and body (laws/NoticeAnswerTellsReads.bend), and neither ranked nor told on
# a transport error: a reader that ranks a run may first read its cold
# shards, and one without the endpoint answers 404.
#
# Why it is trusted: It is HTTP through ezhttp's client, which no law reaches;
# ezhttp's own gate trusts its wire effect (on its src/client.bend and
# src/wire.bend). What a reply means is laws/ReplyIsOkOrFailed.bend.
# `tests/live.sh` runs it against llama-server.
import Base
import ./read.bend as Rd
import ezhttp@0.26.0.0/main.bend as Ez
import ezhttp@0.26.0.0/src/http.bend as Http
import ezhttp@0.26.0.0/src/client.bend as Client
import ezjson@1.5.0.0/main.bend as Json
import ezjson@1.5.0.0/src/value.bend as Value

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

# what a run notice's answer said: whether the instance ranked the run and
# the run's reads it told there, if it told them
type Heard is Data:  # noqa: L001 IO shell type: no law can import this module (foreign effects)
  Heard{ranked: Bool, told: Maybe<&2, List<&2, Rd.Read>>}

# what a notice's response says (Read.ranked, Read.told); a transport error
# says the run was not ranked and tells nothing
def Reader.heard(res: Client.Response, names: List<&2, Rd.Name>, +url: String) -> Heard:
  match res:
    case Client.Err{_why}:
      Heard{False{}, None{}}
    case Client.Response{+status, _headers, _reason, bytes}:
      +text = Ez.body_text(bytes)
      Heard{Rd.Read.ranked(status, text), Rd.Read.told(status, text, names, url)}

# tell the instance at url which shards a run reads, named names; answers
# whether it ranked the run, so its reads can name their shards, and the
# reads it told
def Reader.notice(+url: String, +body: Value.Json, names: List<&2, Rd.Name>) -> IO(Heard):
  do IO<Heard>:
    res : Client.Response <- Ez.http.post_opts(url ++ "/v1/episteme/run",
      [Http.H{"Content-Type", "application/json"}],
      Ez.text_body(Json.print(body)), Reader.notice_timeout())
    return Reader.heard(res, names, url)
