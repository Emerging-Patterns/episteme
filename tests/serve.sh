#!/usr/bin/env bash
# `episteme serve` end to end on the synthetic fixture book: the tool table,
# sources, show (a record, and a missing one), ask refused without a filter
# or a question and with a malformed since, a filter given as a string and
# as an array read alike, and a pool with no healthy instance answered as a
# tool error while the server keeps serving; then, with a reader that ranks
# the run (tests/fixtures/ranker.py), the best ranked printed and all of it
# kept in run files, by `ask` and by the tool. EPISTEME names the binary
# (default bin/episteme); python3 is the MCP client and the ranking reader.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bin=${EPISTEME:-$here/../bin/episteme}
work=$(mktemp -d)
pid=
rpid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; [ -n "$rpid" ] && kill "$rpid" 2>/dev/null; rm -rf "$work"' EXIT

export EPISTEME_HOME=$work/home
mkdir -p "$EPISTEME_HOME"

fail() { echo "serve: FAIL: $*" >&2; exit 1; }

# a pool whose one instance is never up
printf '{"shard_tokens": 100, "chars_per_token": 8000, "pool": [["http://127.0.0.1:1", 2]], "budget_tokens": 60000}\n' \
  > "$EPISTEME_HOME/config.json"
"$bin" ingest records "$here/fixtures/records/tiny-book.jsonl" > /dev/null

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

# a reader that ranks the run names two paragraphs of each shard. A budget
# of 80 characters prints only the best ranked, the 63 characters of the
# gulls, and keeps the two of every shard in run files, the ones not printed
# also in pages
rport=${RANKER_PORT:-18132}
python3 "$here/fixtures/ranker.py" "$rport" &
rpid=$!
for _ in $(seq 100); do
  python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$rport/health', timeout=1)" 2> /dev/null && break
  sleep 0.1
done
printf '{"shard_tokens": 100, "chars_per_token": 8000, "pool": [["http://127.0.0.1:%s", 2]], "budget_tokens": 1}\n' "$rport" \
  > "$EPISTEME_HOME/config.json"
"$bin" ask --filter book:tiny/ "what" > "$work/out.txt" 2> "$work/err.txt" || fail "ask of the ranking reader: $(cat "$work/err.txt")"
[ "$(grep -c '^book:tiny/tiny-book@[0-9]*#[0-9]*: ' "$work/out.txt")" = 1 ] || fail "not one paragraph printed: $(head -c 600 "$work/out.txt")"
grep -q 'seven gulls' "$work/out.txt" || fail "the best ranked is not printed: $(cat "$work/out.txt")"
run=$(sed -n 's/^.* all of it is in \(.*\)\/ (one file per source.*$/\1/p' "$work/out.txt")
[ -f "$run/INDEX.md" ] || fail "no INDEX.md under '$run': $(cat "$work/out.txt")"
shards=$(sed -n 's/^shards: \([0-9]*\) read, 0 failed$/\1/p' "$work/out.txt")
[ -n "$shards" ] && [ "$shards" -ge 2 ] || fail "no footer of at least two shards after the run files: $(tail -n 4 "$work/out.txt")"
named=$(grep -c '^book:tiny/tiny-book@[0-9]*#[0-9]*: ' "$run/book:tiny_tiny-book.md")
[ "$named" = $((2 * shards)) ] || fail "the run file holds $named paragraphs, not two of each of $shards shards"
grep -q 'The Tiny Book' "$run/book:tiny_tiny-book.md" || fail "the run file lacks a paragraph that was not printed"

# the next best are in pages after the printed one: no page repeats what was
# printed, and the pages and the printed paragraph are all that was named
ls "$run"/page-*.md > /dev/null 2>&1 || fail "no page file under $run: $(ls "$run")"
[ -e "$run/page-1.md" ] && fail "the printed page was written as a file"
grep -q 'seven gulls' "$run"/page-*.md && fail "a page repeats the printed paragraph"
paged=$(cat "$run"/page-*.md | grep -c '^book:tiny/tiny-book@[0-9]*#[0-9]*: ')
[ "$paged" = $((named - 1)) ] || fail "the pages hold $paged paragraphs, not the $((named - 1)) named and not printed"
page=$(sed -n '1s/ next-best .*$//p' "$run/INDEX.md")
[ -n "$page" ] && [ -f "$run/$page" ] || fail "INDEX.md does not start with a page of the run: $(cat "$run/INDEX.md")"

# show prints a run file, by its path under the home, for the command and
# the tool alike; a path that climbs out of the run files names no run file
name=$(basename "$run")
grep -q "episteme show runs/$name/<file>" "$work/out.txt" || fail "the run's line does not say how to show a file: $(cat "$work/out.txt")"
"$bin" show "runs/$name/$page" > "$work/page.txt" 2> "$work/err.txt" || fail "show of a page: $(cat "$work/err.txt")"
cmp -s "$work/page.txt" "$run/$page" || fail "show of a page is not the page file"
out=$(call show "{\"id\": \"runs/$name/INDEX.md\"}")
case "$out" in "False	$page next-best "*) ;; *) fail "the tool's show of INDEX.md: $out" ;; esac
out=$(call show "{\"id\": \"runs/$name/nope.md\"}")
[ "$out" = "True	no run file runs/$name/nope.md" ] || fail "show of a missing run file: $out"
out=$(call show '{"id": "runs/../config.json"}')
[ "$out" = "True	no record runs/../config.json" ] || fail "show of a path out of the run files: $out"

out=$(call ask '{"question": "what", "filter": "book:tiny/"}')
case "$out" in "False	### "*"seven gulls"*" all of it is in "*"INDEX.md lists them)"*"episteme show runs/"*" next-best "*"book:tiny_tiny-book.md book:tiny/tiny-book "*) ;; *) fail "the tool's ask of the ranking reader: $out" ;; esac

# a budget that fits all of them prints them and writes no run files
runs=$(ls "$EPISTEME_HOME/runs" | wc -l)
sed -i 's/"budget_tokens": 1}/"budget_tokens": 60000}/' "$EPISTEME_HOME/config.json"
"$bin" ask --filter book:tiny/ "what" > "$work/out.txt" 2> "$work/err.txt" || fail "ask of the ranking reader, whole: $(cat "$work/err.txt")"
[ "$(grep -c '^book:tiny/tiny-book@[0-9]*#[0-9]*: ' "$work/out.txt")" = "$named" ] || fail "a whole run does not print all $named paragraphs: $(head -c 600 "$work/out.txt")"
grep -q ' all of it is in ' "$work/out.txt" && fail "a whole run names run files: $(cat "$work/out.txt")"
[ "$(ls "$EPISTEME_HOME/runs" | wc -l)" = "$runs" ] || fail "a whole run wrote run files"

echo "serve: ok"
