"""A reader that ranks a run, for tests/serve.sh: it answers /health, says
"ranked" to the run notice, and names p1 and p2 of every shard it is read
by name, p2 of shard n ranked 2n - 1 and p1 ranked 2n. usage: ranker.py <port>"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer


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
        self.send(200 if self.path == "/health" else 404, {"status": "ok"})

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if self.path == "/v1/episteme/run":
            return self.send(200, {"ranked": True})
        if self.path != "/v1/episteme/read":
            return self.send(404, {"error": "not found"})
        n = int(req["n"])
        answer = {"ids": ["p1", "p2"], "ranks": [2 * n, 2 * n - 1]}
        self.send(200, {"choices": [{"message": {"role": "assistant", "content": json.dumps(answer)}}]})

    def log_message(self, fmt, *args):
        pass


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
