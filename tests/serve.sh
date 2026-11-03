#!/usr/bin/env bash
# `episteme serve` end to end on the synthetic fixture book: the tool table,
# sources, show (a record, and a missing one), ask refused without a filter
# or a question and with a malformed since, a filter given as a string and
# as an array read alike, and a pool with no healthy instance answered as a
# tool error while the server keeps serving. EPISTEME names the binary
# (default bin/episteme); python3 is the MCP client.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bin=${EPISTEME:-$here/../bin/episteme}
work=$(mktemp -d)
pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$work"' EXIT

export EPISTEME_HOME=$work/home
export EPISTEME_BOOKS=$work/books
mkdir -p "$EPISTEME_HOME" "$EPISTEME_BOOKS/tiny/text"

fail() { echo "serve: FAIL: $*" >&2; exit 1; }

for ext in txt heads.json pages.json; do
  cp "$here/fixtures/books/tiny/text/tiny-book.$ext" "$EPISTEME_BOOKS/tiny/text/tiny-book.$ext"
done
chmod -R u+w "$EPISTEME_BOOKS"
# a pool whose one instance is never up
printf '{"shard_tokens": 100, "chars_per_token": 8000, "pool": [["http://127.0.0.1:1", 2]], "budget_tokens": 60000}\n' \
  > "$EPISTEME_HOME/config.json"
"$bin" ingest books tiny > /dev/null

port=${SERVE_PORT:-18131}
"$bin" serve --port "$port" 2> "$work/serve.err" &
pid=$!

# one JSON-RPC call; prints the reply's result (or error) as JSON
rpc() {
  python3 - "$port" "$1" "$2" <<'EOF'
import json, sys, time, urllib.request
port, method, params = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
for _ in range(100):
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/mcp", body,
            {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"})
        reply = json.load(urllib.request.urlopen(req, timeout=60))
        break
    except OSError:
        time.sleep(0.1)
else:
    sys.exit("no server")
print(json.dumps(reply.get("result", reply.get("error"))))
EOF
}

# a tool call's isError and text, as "<isError>\t<text>"
call() {
  rpc tools/call "{\"name\": \"$1\", \"arguments\": $2}" | python3 -c '
import json, sys
r = json.load(sys.stdin)
print(str(r.get("isError", False)) + "\t" + "".join(c.get("text", "") for c in r.get("content", [])))'
}

tools=$(rpc tools/list '{}' | python3 -c 'import json,sys; print(" ".join(t["name"] for t in json.load(sys.stdin)["tools"]))')
[ "$tools" = "ask show sources" ] || fail "tools are $tools"

out=$(call sources '{}')
case "$out" in "False	source records paragraphs shards"*"book:tiny/tiny-book "*) ;; *) fail "sources: $out" ;; esac

id=$(grep -o '"id":"book:tiny/tiny-book[^"]*"' "$EPISTEME_HOME"/log/*.jsonl | head -1 | sed 's/.*"id":"//; s/"$//')
out=$(call show "{\"id\": \"$id\"}")
case "$out" in "False	### $id |"*) ;; *) fail "show $id: $out" ;; esac
out=$(call show '{"id": "nope"}')
[ "$out" = "True	no record nope" ] || fail "show nope: $out"

out=$(call ask '{"question": "what"}')
case "$out" in "True	a filter is required"*) ;; *) fail "ask without a filter: $out" ;; esac
out=$(call ask '{"filter": "book:tiny/"}')
[ "$out" = "True	ask needs a question" ] || fail "ask without a question: $out"
out=$(call ask '{"question": "what", "filter": "book:tiny/", "since": "soon"}')
case "$out" in "True	--since takes"*) ;; *) fail "ask with a bad since: $out" ;; esac

# no healthy reader: a tool error, the same for both filter shapes, and the
# server still answers after it
want="True	no reader instance is healthy"
out=$(call ask '{"question": "what", "filter": "book:tiny/"}')
[ "$out" = "$want" ] || fail "ask with no reader: $out"
out=$(call ask '{"question": "what", "filter": ["book:tiny/"]}')
[ "$out" = "$want" ] || fail "ask with an array filter: $out"
out=$(call sources '{}')
case "$out" in "False	"*) ;; *) fail "sources after a refused ask: $out" ;; esac

echo "serve: ok"
