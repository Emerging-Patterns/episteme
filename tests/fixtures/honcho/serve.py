# A fake Honcho for tests/smoke.sh: serves the synthetic messages of a data
# file through the three v3 list endpoints the honcho connector calls,
# paged as Honcho pages them, and refuses every other call with 405. It
# reads the data file on every call, so the smoke test can add messages
# between runs. Usage: serve.py <data.json> <port file> <log file>
# Data: {"<workspace>": {"<session>": [message, ...]}}; a session may be
# {"count": n, "peer": p} for n generated messages gen-<session>-<i>, the
# 99th to the 102nd sharing one created_at across the first page boundary.
import json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

data_path, port_path, log_path = sys.argv[1:4]
KEY = "Bearer smoke-key"


def messages(ws, sid, spec):
    if isinstance(spec, list):
        return spec
    out = []
    for i in range(1, spec["count"] + 1):
        sec = 1000 if 99 <= i <= 102 else i
        out.append({"id": f"gen-{sid}-{i}", "content": f"generated message {i}",
                    "peer_id": spec["peer"], "session_id": sid, "workspace_id": ws,
                    "metadata": {}, "token_count": 3,
                    "created_at": "2026-03-12T%02d:%02d:%02d.000000Z" % (sec // 3600, sec // 60 % 60, sec % 60)})
    return out


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, status, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def refuse(self):
        with open(log_path, "a") as log:
            log.write(f"REFUSED {self.command} {self.path}\n")
        self.answer(405, {"detail": "Method Not Allowed"})

    do_GET = do_PUT = do_DELETE = do_PATCH = refuse

    def do_POST(self):
        url = urlparse(self.path)
        with open(log_path, "a") as log:
            log.write(f"POST {self.path}\n")
        if self.headers.get("Authorization") != KEY:
            return self.answer(401, {"detail": "bad key"})
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        q = parse_qs(url.query)
        page, size = int(q.get("page", ["1"])[0]), min(int(q.get("size", ["50"])[0]), 100)
        data = json.load(open(data_path))
        m = re.fullmatch(r"/v3/workspaces/list", url.path)
        if m:
            items = [{"id": w, "metadata": {}} for w in data]
        elif m := re.fullmatch(r"/v3/workspaces/([^/]+)/sessions/list", url.path):
            items = [{"id": s, "metadata": {}} for s in data.get(m[1], {})]
        elif m := re.fullmatch(r"/v3/workspaces/([^/]+)/sessions/([^/]+)/messages/list", url.path):
            items = messages(m[1], m[2], data.get(m[1], {}).get(m[2], []))
        else:
            return self.refuse()
        pages = (len(items) + size - 1) // size
        self.answer(200, {"items": items[(page - 1) * size:page * size], "total": len(items),
                          "page": page, "size": size, "pages": pages})


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_path + ".tmp", "w") as f:
    f.write(str(server.server_port))
import os
os.rename(port_path + ".tmp", port_path)
server.serve_forever()
