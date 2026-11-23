"""A reader that ranks a run, for tests/serve.sh: it answers /health, says
"ranked" to the run notice, and names p1 and p2 of every shard it is read
by name, p2 of shard n ranked 2n - 1 and p1 ranked 2n. With "tell" it tells
those reads in its answer to the notice instead, one for each shard the
notice names, and answers a read with 500; a notice that says a depth is
told only the labels ranked within it (the fixture counts a depth in
paragraphs). GET /asked says how many reads it was asked for and the depth
the last notice said. usage: ranker.py <port> [tell]"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer


TELL = sys.argv[2:] == ["tell"]
ASKED = [0]  # how many reads were asked for
DEPTH = [None]  # the depth the last notice said


def answer(n, depth=None):
    """what the read of the shard numbered n holds, no deeper than depth"""
    got = [(label, rank) for label, rank in (("p1", 2 * n), ("p2", 2 * n - 1)) if depth is None or rank <= depth]
    return {"ids": [label for label, _ in got], "ranks": [rank for _, rank in got]}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/asked":
            return self.send(200, {"reads": ASKED[0], "depth": DEPTH[0]})
        self.send(200 if self.path == "/health" else 404, {"status": "ok"})

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if self.path == "/v1/episteme/run":
            DEPTH[0] = req.get("depth")
            if TELL:
                return self.send(200, {"ranked": True, "reads": [json.dumps(answer(int(sh["n"]), DEPTH[0])) for sh in req["shards"]]})
            return self.send(200, {"ranked": True})
        if self.path != "/v1/episteme/read":
            return self.send(404, {"error": "not found"})
        ASKED[0] += 1
        if TELL:
            return self.send(500, {"error": "the reads were told"})
        self.send(200, {"choices": [{"message": {"role": "assistant", "content": json.dumps(answer(int(req["n"])))}}]})

    def log_message(self, fmt, *args):
        pass


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
