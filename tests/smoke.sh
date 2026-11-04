#!/usr/bin/env bash
# The IO shell end to end on a synthetic fixture corpus: ingest, shards
# split by source, sources, show, a run with nothing new, a lost cursor
# cache, a crash between the batch and the shards (reads refuse, a bare
# ingest packs), a crash between a source's shards and the covered mark, a
# lost tail, a stale shard size, a crash in the middle of a run, the
# ingest lock (a second ingest refused, the lock removed after a failed
# one), the honcho connector against a fake Honcho, the git
# connector on synthetic repos, the intent file and ingest --all, and ask (with and without --since), its
# telemetry line and eval without readers. Each ingest case ends with no id twice
# in the log and shards byte for byte as a reshard writes them. EPISTEME
# names the binary (default bin/episteme, built with
# `bend main.bend -o bin/episteme`).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bin=${EPISTEME:-$here/../bin/episteme}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export EPISTEME_HOME=$work/home
export EPISTEME_BOOKS=$work/books
mkdir -p "$EPISTEME_HOME" "$EPISTEME_BOOKS"
log=$EPISTEME_HOME/log

fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

# a corpus of the fixture book under one or more names
corpus() {
  local name=$1; shift
  mkdir -p "$EPISTEME_BOOKS/$name/text"
  for book in "$@"; do
    for ext in txt heads.json pages.json; do
      cp "$here/fixtures/books/tiny/text/tiny-book.$ext" "$EPISTEME_BOOKS/$name/text/$book.$ext"
    done
  done
  chmod -R u+w "$EPISTEME_BOOKS/$name"
}

# a config whose shard size is tokens * 80 characters
config() {
  printf '{"shard_tokens": %s, "chars_per_token": 8000, "pool": [["http://127.0.0.1:18130", 2]], "budget_tokens": 60000}\n' \
    "$1" > "$EPISTEME_HOME/config.json"
}

batches() { ls "$log" | wc -l; }

# no record id twice in the log
unique() {
  local dups
  dups=$(cat "$log"/*.jsonl | grep -o '^{"id":"[^"]*"' | sort | uniq -d)
  [ -z "$dups" ] || fail "$1: ids twice in the log: $dups"
}

# every shard of a size holds the one source its directory names
one_source() {
  local d src f
  for d in "$EPISTEME_HOME/shards/$1"/*/; do
    src=$(basename "$d" | sed 's/%2F/\//g; s/%2E/./g; s/%25/%/g')
    for f in "$d"*.json; do
      grep -q "\"sources\":\[\"$src\"\]" "$f" || fail "$2: $f does not hold $src alone"
    done
  done
}

# the frozen shards of the configured size, as paths under its directory
frozen_of() { (cd "$1" && find . -name '*.json' ! -name tail.json ! -name covered.json | sort); }

# the shards of the configured size are those a reshard writes
fresh() {
  local dir=$EPISTEME_HOME/shards/$1
  rm -rf "$work/inc"; cp -r "$dir" "$work/inc"
  "$bin" ingest --reshard > /dev/null
  diff -r "$work/inc" "$dir" > /dev/null || fail "$2: the shards differ from a reshard"
  one_source "$1" "$2"
}

corpus tiny tiny-book tiny-two
config 100
shards=$EPISTEME_HOME/shards/8000

"$bin" ingest books tiny
[ "$(batches)" = 2 ] || fail "one log batch per book after the first ingest"
frozen=$(frozen_of "$shards")
[ -n "$frozen" ] || fail "the fixture should freeze at least one shard"
[ -f "$shards/book:tiny%2Ftiny-book/tail.json" ] || fail "no shard directory for book:tiny/tiny-book: $(ls "$shards")"
[ -f "$shards/book:tiny%2Ftiny-two/tail.json" ] || fail "no shard directory for book:tiny/tiny-two: $(ls "$shards")"
grep -q '^{"covered":2}$' "$shards/covered.json" || fail "the covered mark: $(cat "$shards/covered.json")"
one_source 8000 "first ingest"
head -n 1 "$log/00000002.jsonl" | grep -q '^{"conn":"books","cursor":"tiny/tiny-book.txt\\ntiny/tiny-two.txt\\n"}$' \
  || fail "the batch header does not hold the cursor: $(head -n 1 "$log/00000002.jsonl")"

"$bin" sources > "$work/sources.txt"
grep -q '^book:tiny/tiny-book ' "$work/sources.txt" || fail "sources lacks book:tiny/tiny-book: $(cat "$work/sources.txt")"

# the second record starts at the first heading, offset 49: its paragraph 1
# is the heading line and the line under it, at whole-file offsets 49..112
"$bin" show 'book:tiny/tiny-book@49#1' > "$work/show.txt"
grep -q 'The lantern keeper counted seven gulls before noon.' "$work/show.txt" \
  || fail "show printed: $(cat "$work/show.txt")"
grep -q '\[1,49,112,"Chapter One\\nThe lantern keeper' "$log/00000001.jsonl" \
  || fail "paragraph offsets are not whole-file offsets"

# nothing new: no batch and no file written
cp -r "$shards" "$work/before"
touch "$work/mark"
"$bin" ingest books tiny
[ "$(batches)" = 2 ] || fail "a run with nothing new wrote a log batch"
[ -z "$(find "$EPISTEME_HOME" -type f -newer "$work/mark")" ] || fail "a run with nothing new wrote a file"

# a lost cursor cache: the cursor is in the log
rm "$EPISTEME_HOME/state/books.json"
"$bin" ingest books tiny
[ "$(batches)" = 2 ] || fail "an ingest without its cursor cache wrote a log batch"
for f in $frozen; do cmp "$work/before/$f" "$shards/$f" || fail "frozen shard $f changed"; done
unique "lost cache"

# a crash after the batch and before the shards: put the shards back as
# they were; reads refuse and write nothing, and the next ingest packs the
# batch
corpus later tiny-book
"$bin" ingest books later
[ "$(batches)" = 3 ] || fail "the later book wrote no log batch"
[ -e "$EPISTEME_HOME/lock" ] && fail "an ingest left its lock"
for f in $frozen; do cmp "$work/before/$f" "$shards/$f" || fail "frozen shard $f changed on append"; done
cp -r "$shards" "$work/after"
rm -rf "$shards"
cp -r "$work/before" "$shards"
rc=0; "$bin" sources > /dev/null 2> "$work/err.txt" || rc=$?
[ "$rc" = 1 ] || fail "sources over shards behind the log exited $rc, not 1"
grep -q 'shards hold log batches up to 2 of 3; run episteme ingest$' "$work/err.txt" \
  || fail "no behind refusal from sources: $(cat "$work/err.txt")"
rc=0; "$bin" ask --filter book:later/ "q" > /dev/null 2> "$work/err.txt" || rc=$?
[ "$rc" = 1 ] || fail "ask over shards behind the log exited $rc, not 1"
grep -q 'shards hold log batches up to 2 of 3; run episteme ingest$' "$work/err.txt" \
  || fail "no behind refusal from ask: $(cat "$work/err.txt")"
diff -r "$work/before" "$shards" > /dev/null || fail "a read wrote the shards"
"$bin" ingest books later 2> "$work/err.txt"
grep -q 'packed log batches 3 to 3' "$work/err.txt" || fail "no catch-up: $(cat "$work/err.txt")"
[ "$(batches)" = 3 ] || fail "a re-run after a crash wrote a log batch"
diff -r "$work/after" "$shards" > /dev/null || fail "the caught-up shards differ"
unique "crash"
fresh 8000 "crash"

# a crash after a source's shards and before the covered mark: the source
# is caught up from its own tail, and its batch is not packed twice
corpus again tiny-book
"$bin" ingest books again
[ "$(batches)" = 4 ] || fail "the again book wrote no log batch"
[ -f "$shards/book:again%2Ftiny-book/tail.json" ] || fail "a source new in a batch got no shards"
cp "$work/after/covered.json" "$shards/covered.json"
"$bin" ingest 2> "$work/err.txt"
grep -q 'packed log batches 4 to 4' "$work/err.txt" || fail "no catch-up after the mark: $(cat "$work/err.txt")"
grep -q '^{"covered":4}$' "$shards/covered.json" || fail "the mark did not move: $(cat "$shards/covered.json")"
unique "mark"
fresh 8000 "mark"

# a lost tail: a source directory without tail.json, the mark kept and
# then behind its batch, is refused by a read and by an ingest's sync
# rather than packed again from an empty tail over its frozen shard 1, the
# failed ingest removing its lock; a reshard mends it
rm -rf "$work/lost"; cp -r "$shards" "$work/lost"
rm "$shards/book:again%2Ftiny-book/tail.json"
if "$bin" sources > /dev/null 2> "$work/err.txt"; then fail "a source without its tail was read"; fi
grep -q 'book:again%2Ftiny-book has no tail.json; run episteme ingest --reshard' "$work/err.txt" \
  || fail "no lost-tail refusal on read: $(cat "$work/err.txt")"
cp "$work/after/covered.json" "$shards/covered.json"
if "$bin" ingest > /dev/null 2> "$work/err.txt"; then fail "a sync packed onto a lost tail"; fi
grep -q 'has no tail.json; run episteme ingest --reshard' "$work/err.txt" \
  || fail "no lost-tail refusal on sync: $(cat "$work/err.txt")"
[ -e "$EPISTEME_HOME/lock" ] && fail "a failed ingest left its lock"
cmp "$work/lost/book:again%2Ftiny-book/00000001.json" "$shards/book:again%2Ftiny-book/00000001.json" \
  || fail "frozen shard 1 was written over"
"$bin" ingest --reshard > /dev/null 2>&1 || fail "the reshard after a lost tail failed"
diff -r "$work/lost" "$shards" > /dev/null || fail "the reshard after a lost tail differs"

# a stale size: ingest at 8080 characters, then back at 8000, which has
# missed two batches
config 101
corpus third tiny-book
corpus fourth tiny-book
"$bin" ingest books third
"$bin" ingest books fourth
[ "$(batches)" = 6 ] || fail "the 8080 ingests wrote no batches"
fresh 8080 "other size"
config 100
"$bin" ingest 2> "$work/err.txt"
grep -q 'packed log batches 5 to 6' "$work/err.txt" || fail "the stale size was not caught up: $(cat "$work/err.txt")"
"$bin" sources | grep -q '^book:fourth/tiny-book ' || fail "sources lacks book:fourth/tiny-book"
unique "stale size"
fresh 8000 "stale size"

# a crash in the middle of a run, then a run over another corpus that has
# nothing new, then the first again: only the book the crash lost is added
corpus pair pair-one pair-two
cp -r "$EPISTEME_HOME" "$work/home-before-pair"
"$bin" ingest books pair
[ "$(batches)" = 8 ] || fail "the pair corpus wrote no batches"
rm "$log/00000008.jsonl"
rm -rf "$EPISTEME_HOME/shards"
cp -r "$work/home-before-pair/shards" "$EPISTEME_HOME/shards"
"$bin" ingest books tiny
[ "$(batches)" = 7 ] || fail "a run with nothing new wrote a log batch after the crash"
"$bin" ingest books pair > "$work/pair.txt"
grep -q '^book:pair/pair-one: 0 records' "$work/pair.txt" && fail "pair-one ran again"
grep -q '^book:pair/pair-two: 6 records' "$work/pair.txt" || fail "pair-two was not added: $(cat "$work/pair.txt")"
[ "$(batches)" = 8 ] || fail "the pair re-run did not add one batch"
unique "crash in a run"
fresh 8000 "crash in a run"

# the lock: while it exists a second ingest refuses, naming it, writes
# nothing and leaves the lock for its holder
corpus locked tiny-book
mkdir "$EPISTEME_HOME/lock"
touch "$work/mark"
rc=0; "$bin" ingest books locked > /dev/null 2> "$work/err.txt" || rc=$?
[ "$rc" = 1 ] || fail "an ingest while the lock exists exited $rc, not 1"
grep -qF "$EPISTEME_HOME/lock exists: another ingest is running; if none is, remove it by hand" "$work/err.txt" \
  || fail "no lock refusal: $(cat "$work/err.txt")"
[ -d "$EPISTEME_HOME/lock" ] || fail "a refused ingest removed the lock"
[ -z "$(find "$EPISTEME_HOME" -type f -newer "$work/mark")" ] || fail "a refused ingest wrote a file"
rmdir "$EPISTEME_HOME/lock"
rm -rf "$EPISTEME_BOOKS/locked"

# the claude connector on a synthetic transcript and one subagent
# transcript: 10 lines give 7 records (no compaction summary, no system
# line, no queued task notification; a human's queued prompt is one), the
# tool result and a tool call over 4000 code points are pointers that
# show resolves to their lines, a second run reads nothing, and a line
# still being written waits until its line feed lands
export EPISTEME_CLAUDE=$work/claude
cp -r "$here/fixtures/claude" "$EPISTEME_CLAUDE"
chmod -R u+w "$EPISTEME_CLAUDE"
proj=$EPISTEME_CLAUDE/-home-x-proj
sess=$proj/0c0ffee0-0000-4000-8000-000000000001.jsonl
"$bin" ingest claude > "$work/claude.txt"
grep -q '^chat:claude: 7 records$' "$work/claude.txt" || fail "the fixture transcripts gave: $(cat "$work/claude.txt")"
[ "$(batches)" = 9 ] || fail "the claude ingest wrote no single batch"
# each entry is <lines>\t<bytes>\t<file>: the fixtures end with a line
# feed, so the bytes are each file's size
subs=$proj/0c0ffee0-0000-4000-8000-000000000001/subagents/agent-0001.jsonl
head -n 1 "$log/00000009.jsonl" | grep -q "\"cursor\":\"2\\\\t$(wc -c < "$subs")\\\\t-home-x-proj/0c0ffee0-0000-4000-8000-000000000001/subagents/agent-0001.jsonl\\\\n8\\\\t$(wc -c < "$sess")\\\\t-home-x-proj/0c0ffee0-0000-4000-8000-000000000001.jsonl\\\\n\"" \
  || fail "the claude batch header: $(head -n 1 "$log/00000009.jsonl")"
"$bin" sources | grep -q '^chat:claude/home-x-proj 7 ' || fail "sources lacks chat:claude/home-x-proj with 7 records"
grep -q 'compact-summary-marker' "$log/00000009.jsonl" && fail "the compaction summary was ingested"
grep -q 'system-line-marker' "$log/00000009.jsonl" && fail "a system line was ingested"
grep -q 'notification-marker' "$log/00000009.jsonl" && fail "a queued task notification was ingested"
"$bin" show 'claude:00000000-0000-4000-8000-0000000000a7' > "$work/show.txt"
grep -q '| noah$' "$work/show.txt" || fail "the queued prompt's author: $(cat "$work/show.txt")"
grep -q '#1: Also count the lanterns.$' "$work/show.txt" || fail "the queued prompt: $(cat "$work/show.txt")"
grep -q 'sleep in the east room' "$log/00000009.jsonl" && fail "a tool result's text was ingested"
"$bin" show 'claude:00000000-0000-4000-8000-0000000000a4:0' > "$work/show.txt"
grep -q '| tool$' "$work/show.txt" || fail "the tool result's author: $(cat "$work/show.txt")"
grep -q '#1: tool result, 30 chars$' "$work/show.txt" || fail "the tool result's body: $(cat "$work/show.txt")"
grep -q '"uuid":"00000000-0000-4000-8000-0000000000a4".*keepers sleep in the east room' "$work/show.txt" \
  || fail "show did not print the transcript's line 4: $(cat "$work/show.txt")"
"$bin" show 'claude:00000000-0000-4000-8000-0000000000a2' > "$work/show.txt"
grep -q '| claude-test-1$' "$work/show.txt" || fail "the assistant's author: $(cat "$work/show.txt")"
grep -q '#1: The tower log should say.$' "$work/show.txt" || fail "the thinking: $(cat "$work/show.txt")"
grep -q '#2: Let me check the tower log.$' "$work/show.txt" || fail "the text: $(cat "$work/show.txt")"
"$bin" show 'claude:00000000-0000-4000-8000-0000000000a3:0' | grep -q '#1: Read$' || fail "the tool call's name"
"$bin" show 'claude:00000000-0000-4000-8000-0000000000a1' | grep -q '| noah$' || fail "the user's author"
"$bin" show 'claude:00000000-0000-4000-8000-0000000000b1' | grep -q '| agent$' || fail "the subagent prompt's author"
grep -q 'xxxxxxxxxx' "$log/00000009.jsonl" && fail "a big tool call's input was ingested"
"$bin" show 'claude:00000000-0000-4000-8000-0000000000b2:0' > "$work/show.txt"
grep -q '#1: Bash, 4119 chars$' "$work/show.txt" || fail "the big tool call's body: $(cat "$work/show.txt")"
grep -q '| claude-test-1$' "$work/show.txt" || fail "the big tool call's author: $(cat "$work/show.txt")"
grep -q '"uuid":"00000000-0000-4000-8000-0000000000b2".*echo xxxx' "$work/show.txt" \
  || fail "show did not print the big tool call's line: $(cat "$work/show.txt")"
"$bin" ingest claude > "$work/claude.txt"
[ "$(batches)" = 9 ] || fail "a claude run with nothing new wrote a batch"
line='{"type":"user","uuid":"00000000-0000-4000-8000-0000000000a9","parentUuid":null,"sessionId":"0c0ffee0-0000-4000-8000-000000000001","timestamp":"2026-10-01T10:06:00.000Z","message":{"role":"user","content":"And the gulls?"}}'
printf '%s' "${line:0:60}" >> "$sess"
"$bin" ingest claude > /dev/null
[ "$(batches)" = 9 ] || fail "a line still being written was read"
printf '%s\n' "${line:60}" >> "$sess"
"$bin" ingest claude > "$work/claude.txt"
grep -q '^chat:claude: 1 records$' "$work/claude.txt" || fail "the finished line gave: $(cat "$work/claude.txt")"
[ "$(batches)" = 10 ] || fail "the finished line wrote no batch"
unique "claude"
fresh 8000 "claude"
unset EPISTEME_CLAUDE

# the honcho connector against a fake Honcho (tests/fixtures/honcho/serve.py)
# serving synthetic messages: 353 messages in four sessions give 352
# records (one has empty content), a session of 250 is read over three
# pages with four messages of one created_at across the first page
# boundary, a session of exactly 100 ends at an empty page 2, a second run
# reads nothing, messages added later are read once, a session at a
# partial page grown by more than a page is read once, every call is a
# list POST, and a Honcho that cannot be reached appends nothing, exits 1
# and removes the ingest lock
cp "$here/fixtures/honcho/data.json" "$work/honcho.json"
chmod u+w "$work/honcho.json"
python3 "$here/fixtures/honcho/serve.py" "$work/honcho.json" "$work/honcho.port" "$work/honcho.log" &
hpid=$!
trap 'kill "$hpid" 2> /dev/null || true; rm -rf "$work"' EXIT
for _ in $(seq 100); do [ -s "$work/honcho.port" ] && break; sleep 0.1; done
[ -s "$work/honcho.port" ] || fail "the fake Honcho did not start"
export HONCHO_BASE_URL=http://127.0.0.1:$(cat "$work/honcho.port") HONCHO_API_KEY=smoke-key
"$bin" ingest honcho > "$work/honcho.txt"
grep -q '^chat:honcho: 352 records, 353 messages read$' "$work/honcho.txt" || fail "the fake Honcho gave: $(cat "$work/honcho.txt")"
[ "$(batches)" = 11 ] || fail "the honcho ingest wrote no single batch"
head -n 1 "$log/00000011.jsonl" | grep -q '"cursor":"3\\tws-a/s-small\\n0\\tws-a/s-empty\\n250\\tws-b/s-big\\n100\\tws-b/s-hundred\\n"' \
  || fail "the honcho batch header: $(head -n 1 "$log/00000011.jsonl")"
"$bin" sources | grep -q '^chat:honcho 352 ' || fail "sources lacks chat:honcho with 352 records"
grep -q '"id":"honcho:hm-3"' "$log/00000011.jsonl" && fail "a message with empty content made a record"
"$bin" show 'honcho:hm-2' > "$work/show.txt"
grep -q '^### honcho:hm-2 | chat:honcho | 2026-03-11T18:26:04.684915Z | claude$' "$work/show.txt" \
  || fail "the honcho record's header: $(cat "$work/show.txt")"
grep -q '^honcho:hm-2#2: The tower log says so.$' "$work/show.txt" || fail "the honcho record's body: $(cat "$work/show.txt")"
grep -q '"id":"honcho:hm-1".*"thread":"ws-a/s-small"' "$log/00000011.jsonl" || fail "the honcho record's thread"
for i in 99 100 101 102 250; do
  [ "$(grep -c "\"id\":\"honcho:gen-s-big-$i\"" "$log/00000011.jsonl")" = 1 ] || fail "gen-s-big-$i is not in the log once"
done
"$bin" ingest honcho > "$work/honcho.txt"
grep -q '^chat:honcho: 0 records, 0 messages read$' "$work/honcho.txt" || fail "a second honcho run read: $(cat "$work/honcho.txt")"
[ "$(batches)" = 11 ] || fail "a honcho run with nothing new wrote a batch"
python3 - "$work/honcho.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["ws-a"]["s-small"].append({"id": "hm-4", "content": "And the gulls?", "peer_id": "noah", "session_id": "s-small", "workspace_id": "ws-a", "metadata": {}, "token_count": 4, "created_at": "2026-03-11T18:27:00.000000Z"})
d["ws-b"]["s-big"]["count"] = 252
d["ws-b"]["s-hundred"]["count"] = 101
json.dump(d, open(sys.argv[1], "w"))
PY
"$bin" ingest honcho > "$work/honcho.txt"
grep -q '^chat:honcho: 4 records, 4 messages read$' "$work/honcho.txt" || fail "the added messages gave: $(cat "$work/honcho.txt")"
[ "$(batches)" = 12 ] || fail "the added messages wrote no batch"
grep -q '"id":"honcho:gen-s-hundred-101"' "$log/00000012.jsonl" || fail "the 101st message of s-hundred was not read"
# a session at a partial page (s-big at 252) grows by more than a page
python3 - "$work/honcho.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["ws-b"]["s-big"]["count"] = 410
json.dump(d, open(sys.argv[1], "w"))
PY
"$bin" ingest honcho > "$work/honcho.txt"
grep -q '^chat:honcho: 158 records, 158 messages read$' "$work/honcho.txt" || fail "the grown session gave: $(cat "$work/honcho.txt")"
[ "$(batches)" = 13 ] || fail "the grown session wrote no batch"
head -n 1 "$log/00000013.jsonl" | grep -q '410\\tws-b/s-big' || fail "the grown session's count: $(head -n 1 "$log/00000013.jsonl")"
for i in 252 253 300 301 400 401 410; do
  [ "$(cat "$log"/*.jsonl | grep -c "\"id\":\"honcho:gen-s-big-$i\"")" = 1 ] || fail "gen-s-big-$i is not in the log once"
done
grep -q 'REFUSED' "$work/honcho.log" && fail "the connector made a call that is no list POST: $(grep REFUSED "$work/honcho.log")"
grep -qv '^POST /v3/workspaces/[^?]*list?page=[0-9]*&size=100$' "$work/honcho.log" \
  && fail "a call other than a list page: $(grep -v '^POST /v3/workspaces/[^?]*list?page=[0-9]*&size=100$' "$work/honcho.log")"
unique "honcho"
fresh 8000 "honcho"
rc=0; HONCHO_BASE_URL=http://127.0.0.1:9 "$bin" ingest honcho > /dev/null 2> "$work/err.txt" || rc=$?
[ "$rc" = 1 ] || fail "a honcho run with no Honcho exited $rc, not 1"
grep -q 'cannot list workspaces; nothing appended' "$work/err.txt" || fail "no honcho refusal: $(cat "$work/err.txt")"
[ "$(batches)" = 13 ] || fail "a honcho run with no Honcho wrote a batch"
[ -e "$EPISTEME_HOME/lock" ] && fail "a honcho run with no Honcho left the lock"
kill "$hpid"

# the git connector on synthetic repos (tests/fixtures/git/make.sh): a repo
# of 3 commits and a nested one of 1 under bend/, a directory that is no
# repo skipped, author times with UTC offsets read as UTC, the pointer that
# show resolves to the commit's patch, a second run that reads nothing, a
# new commit read once, an amended commit read once, a branch read and then
# main again reading nothing, a rewritten commit whose old tip was pruned
# read alone, a message holding U+001E read, and a repo made again whose
# tips are gone read whole
export EPISTEME_PROJECTS=$work/projects
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS"
repo=$EPISTEME_PROJECTS/fixrepo
"$bin" ingest git > "$work/git.txt"
grep -q '^git: 4 records, 4 commits read, 2 repos$' "$work/git.txt" || fail "the fixture repos gave: $(cat "$work/git.txt")"
[ "$(batches)" = 14 ] || fail "the git ingest wrote no single batch"
head -n 1 "$log/00000014.jsonl" | grep -q "\"cursor\":\"$(git -C "$repo" rev-parse HEAD)\\\\t$repo\\\\n" \
  || fail "the git batch header: $(head -n 1 "$log/00000014.jsonl")"
"$bin" sources > "$work/sources.txt"
grep -q '^git:fixrepo 3 ' "$work/sources.txt" || fail "sources lacks git:fixrepo with 3 records: $(cat "$work/sources.txt")"
grep -q '^git:nested 1 ' "$work/sources.txt" || fail "sources lacks git:nested with 1 record: $(cat "$work/sources.txt")"
grep -q '^git:plain ' "$work/sources.txt" && fail "a directory that is no repo was read"
grep -q '^git:fixrepo-wt ' "$work/sources.txt" && fail "a linked worktree was read as its own repo"
first=$(git -C "$repo" rev-parse HEAD~2)
"$bin" show "git:fixrepo@$first" > "$work/show.txt"
grep -q "^### git:fixrepo@$first | git:fixrepo | 2025-12-31T20:30:00.000Z | Fixture Keeper\$" "$work/show.txt" \
  || fail "the git record's header: $(cat "$work/show.txt")"
grep -q "^git:fixrepo@$first#2: The keeper writes one line a day.\$" "$work/show.txt" || fail "the commit message: $(cat "$work/show.txt")"
grep -q "^git:fixrepo@$first#3: files:\$" "$work/show.txt" || fail "the files list: $(cat "$work/show.txt")"
grep -q '^diff --git a/lantern.txt b/lantern.txt$' "$work/show.txt" || fail "show did not print the patch: $(cat "$work/show.txt")"
grep -q '^+The lantern keeper counted seven gulls.$' "$work/show.txt" || fail "show did not print the patch's lines"
"$bin" show "git:fixrepo@$(git -C "$repo" rev-parse HEAD~1)" > "$work/show.txt"
grep -q '| 2026-02-03T18:00:00.000Z | Fixture Keeper$' "$work/show.txt" \
  || fail "a negative UTC offset was not read as UTC: $(cat "$work/show.txt")"
grep -q '"files:\\n-\\t-\\tseal.bin"' "$log/00000014.jsonl" || fail "the binary file's numstat line"
"$bin" ingest git > "$work/git.txt"
grep -q '^git: 0 records, 0 commits read, 2 repos$' "$work/git.txt" || fail "a second git run read: $(cat "$work/git.txt")"
[ "$(batches)" = 14 ] || fail "a git run with nothing new wrote a batch"
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS" more
"$bin" ingest git > "$work/git.txt"
grep -q '^git: 1 records, 1 commits read, 2 repos$' "$work/git.txt" || fail "a new commit gave: $(cat "$work/git.txt")"
grep -q '"Log the dusk count"' "$log/00000015.jsonl" || fail "the new commit is not in its batch"
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS" amend
"$bin" ingest git > "$work/git.txt"
grep -q '^git: 1 records, 1 commits read, 2 repos$' "$work/git.txt" || fail "an amended commit gave: $(cat "$work/git.txt")"
grep -q '"Log the dusk count again"' "$log/00000016.jsonl" || fail "the amended commit is not in its batch"
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS" branch
"$bin" ingest git > "$work/git.txt"
grep -q '^git: 1 records, 1 commits read, 2 repos$' "$work/git.txt" || fail "a side branch gave: $(cat "$work/git.txt")"
tips=$(head -n 1 "$log/00000017.jsonl" | grep -o "\"cursor\":\"[0-9a-f ]*\\\\t$repo\\\\n")
for tip in "$(git -C "$repo" rev-parse side)" "$(git -C "$repo" rev-parse main)"; do
  case $tips in *$tip*) ;; *) fail "the cursor does not hold tip $tip: $(head -n 1 "$log/00000017.jsonl")" ;; esac
done
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS" back
"$bin" ingest git > "$work/git.txt"
grep -q '^git: 0 records, 0 commits read, 2 repos$' "$work/git.txt" || fail "main again after a branch read: $(cat "$work/git.txt")"
[ "$(batches)" = 17 ] || fail "main again after a branch wrote a batch"
old=$(git -C "$repo" rev-parse main)
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS" prune
git -C "$repo" cat-file -e "$old" 2> /dev/null && fail "the pruned tip is still in the repo"
"$bin" ingest git > "$work/git.txt" 2> "$work/err.txt"
grep -q '^git: 1 records, 1 commits read, 2 repos$' "$work/git.txt" || fail "a rewrite past a pruned tip gave: $(cat "$work/git.txt")"
grep -q '"Log the dusk count once more"' "$log/00000018.jsonl" || fail "the rewritten commit is not in its batch"
[ -s "$work/err.txt" ] && fail "a pruned tip said: $(cat "$work/err.txt")"
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS" rs
"$bin" ingest git > "$work/git.txt"
grep -q '^git: 1 records, 1 commits read, 2 repos$' "$work/git.txt" || fail "a message holding U+001E gave: $(cat "$work/git.txt")"
grep -q '"Mark the tide \\u001e record"' "$log/00000019.jsonl" || fail "the U+001E message: $(tail -n 1 "$log/00000019.jsonl")"
bash "$here/fixtures/git/make.sh" "$EPISTEME_PROJECTS" renest
"$bin" ingest git > "$work/git.txt" 2> "$work/err.txt"
grep -q '^git: 1 records, 1 commits read, 2 repos$' "$work/git.txt" || fail "a nested repo made again gave: $(cat "$work/git.txt")"
[ -s "$work/err.txt" ] && fail "a repo made again said: $(cat "$work/err.txt")"
"$bin" sources > "$work/sources.txt"
grep -q '^git:fixrepo 8 ' "$work/sources.txt" || fail "git:fixrepo does not hold 8 records: $(cat "$work/sources.txt")"
grep -q '^git:nested 2 ' "$work/sources.txt" || fail "git:nested does not hold 2 records: $(cat "$work/sources.txt")"
[ "$(batches)" = 20 ] || fail "the git runs wrote $(batches) batches, not 20"
unique "git"
fresh 8000 "git"

# the intent connector: a missing intent.md is made empty and appends
# nothing; a text is one record of the whole file, by noah, the text the
# batch's cursor; the same text again appends nothing; a changed text
# appends one more; an empty file appends nothing
intent=$EPISTEME_HOME/intent.md
rm -f "$intent"
"$bin" ingest intent > "$work/intent.txt"
grep -q '^intent: 0 records$' "$work/intent.txt" || fail "a missing intent.md gave: $(cat "$work/intent.txt")"
[ -f "$intent" ] && [ ! -s "$intent" ] || fail "a missing intent.md was not made empty"
printf 'Ship the skill.\n\nThen rest.\n' > "$intent"
"$bin" ingest intent > "$work/intent.txt"
grep -q '^intent: 1 records$' "$work/intent.txt" || fail "a first intent text gave: $(cat "$work/intent.txt")"
[ "$(batches)" = 21 ] || fail "the intent text wrote no single batch"
head -n 1 "$log/00000021.jsonl" | grep -qF '{"conn":"intent","cursor":"Ship the skill.\n\nThen rest.\n"}' \
  || fail "the intent batch header: $(head -n 1 "$log/00000021.jsonl")"
grep -q '"id":"intent@[^"]*","ts":"[^"]*","source":"intent","author":"noah",.*\[2,17,27,"Then rest."\]' "$log/00000021.jsonl" \
  || fail "the intent record: $(tail -n 1 "$log/00000021.jsonl")"
"$bin" ingest intent > "$work/intent.txt"
grep -q '^intent: 0 records$' "$work/intent.txt" || fail "the same intent text gave: $(cat "$work/intent.txt")"
[ "$(batches)" = 21 ] || fail "the same intent text wrote a batch"
# --all runs claude, git and intent, then honcho, which exits 1 with no
# Honcho
printf 'Ship the skill.\n\nThen rest more.\n' > "$intent"
rc=0; EPISTEME_CLAUDE=$work/claude HONCHO_BASE_URL=http://127.0.0.1:9 "$bin" ingest --all > "$work/all.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 1 ] || fail "ingest --all with no Honcho exited $rc, not 1"
[ "$(cat "$work/all.txt")" = "$(printf 'chat:claude: 0 records\ngit: 0 records, 0 commits read, 2 repos\nintent: 1 records')" ] \
  || fail "ingest --all printed: $(cat "$work/all.txt")"
grep -q 'cannot list workspaces; nothing appended' "$work/err.txt" || fail "ingest --all did not reach honcho: $(cat "$work/err.txt")"
[ "$(batches)" = 22 ] || fail "the changed intent text wrote no single batch"
: > "$intent"
"$bin" ingest intent > "$work/intent.txt"
grep -q '^intent: 0 records$' "$work/intent.txt" || fail "an empty intent.md gave: $(cat "$work/intent.txt")"
"$bin" sources | grep -q '^intent 2 ' || fail "sources lacks intent with 2 records"
unique "intent"
fresh 8000 "intent"
unset EPISTEME_PROJECTS

# config refusals: a field missing, by name
mv "$EPISTEME_HOME/config.json" "$work/config.json"
sed 's/, "budget_tokens": 60000//' "$work/config.json" > "$EPISTEME_HOME/config.json"
if "$bin" sources 2> "$work/err.txt"; then fail "a config without budget_tokens was read"; fi
grep -q 'budget_tokens' "$work/err.txt" || fail "the refusal does not name the field: $(cat "$work/err.txt")"
mv "$work/config.json" "$EPISTEME_HOME/config.json"

# ask without readers: a refused filter exits 2 with the refusal, a filter
# that hits no shard asks no reader, and a pool with no healthy instance
# exits 2 naming each skipped URL
rc=0; "$bin" ask "q" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask with no filter exited $rc, not 2"
grep -q 'a filter is required' "$work/err.txt" || fail "no refusal: $(cat "$work/err.txt")"
rc=0; "$bin" ask --filter chat:claude/ "q" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask over every chat exited $rc, not 2"
printf '{"shard_tokens": 100, "chars_per_token": 8000, "pool": [["http://127.0.0.1:9", 2]], "budget_tokens": 60000}\n' \
  > "$EPISTEME_HOME/config.json"
"$bin" ask --filter book:none/ "q" > "$work/out.txt" || fail "ask over no shard failed"
grep -q '^shards: 0 read, 0 failed$' "$work/out.txt" || fail "no footer for no shard: $(cat "$work/out.txt")"
# --since: a malformed value exits 2 with its refusal; a since after every
# record reads no shard and asks no reader
rc=0; "$bin" ask --filter book:tiny/ --since 2026-1-24 "q" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask with a malformed --since exited $rc, not 2"
grep -q '^episteme: --since takes YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS.mmmZ, not 2026-1-24$' "$work/err.txt" \
  || fail "no --since refusal: $(cat "$work/err.txt")"
"$bin" ask --filter book:tiny/ --since 2999-01-01 "q" > "$work/out.txt" || fail "ask since after every record failed"
grep -q '^shards: 0 read, 0 failed$' "$work/out.txt" || fail "a since after every record read: $(cat "$work/out.txt")"
# eval without readers: a question whose filter hits no shard scores 0 of
# 1 and writes its report; a line that is no question exits 1; a label
# with / and a refused filter exit 2
printf '{"id":"q1","question":"q","filter":["book:none/"],"gold":[{"source":"book:none/x","start":0,"end":5}],"answer":"a"}\n' \
  > "$work/q.jsonl"
"$bin" eval "$work/q.jsonl" --label smoke > "$work/out.txt" 2> "$work/err.txt" || fail "eval over no shard failed: $(cat "$work/err.txt")"
grep -q '^| smoke | 1 | 0.0% | 0 | 1 | 0 |' "$work/out.txt" || fail "eval printed: $(cat "$work/out.txt")"
grep -q '"recalled":0,"gold":1' "$EPISTEME_HOME"/runs/eval-smoke-*/report.json || fail "no eval report"
echo 'not json' > "$work/bad.jsonl"
rc=0; "$bin" eval "$work/bad.jsonl" --label bad > /dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "eval of a line that is no question exited $rc, not 1"
rc=0; "$bin" eval "$work/q.jsonl" --label a/b > /dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "eval with a label holding / exited $rc, not 2"
printf '{"id":"c1","question":"q","filter":["chat:claude/"],"gold":[]}\n' > "$work/chat.jsonl"
rc=0; "$bin" eval "$work/chat.jsonl" --label chat 2> "$work/err.txt" > /dev/null || rc=$?
[ "$rc" = 2 ] || fail "eval over every chat exited $rc, not 2"
grep -q '^episteme: c1: a filter is required' "$work/err.txt" || fail "no eval refusal: $(cat "$work/err.txt")"
rc=0; "$bin" ask --filter book:tiny/ "q" > "$work/out.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask with no healthy reader exited $rc, not 2"
grep -q '^skipping http://127.0.0.1:9: ' "$work/err.txt" || fail "the dead reader is not named: $(cat "$work/err.txt")"
# telemetry: that question's line is the last, refused with exit 2 and no
# reads, naming the source the filter hit and the shards it would have read;
# the eval's line says it came from eval
tele=$EPISTEME_HOME/telemetry.jsonl
line=$(tail -n 1 "$tele")
for want in '"via":"ask","question":"q","filter":["book:tiny/"],"since":null,' '"code":2,"refused":"' \
  '"sources":[{"source":"book:tiny/tiny-book","shards":' '"shards":[{"source":"book:tiny/tiny-book","n":1,"chars":' \
  '"ok":false,"ms":0,"labels":0,"out_paras":0,"out_chars":0}' '"excerpts":0,"out_chars":0}'; do
  case $line in *"$want"*) ;; *) fail "the telemetry line lacks $want: $line" ;; esac
done
grep -qF '"via":"eval","question":"q","filter":["book:none/"],' "$tele" || fail "no eval telemetry line"
rc=0; "$bin" ask --filter book:tiny/ --since 2000-01-01T00:00:00.000Z "q" > "$work/out.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask since before every record exited $rc, not 2: no shard reached the dead pool"
config 100

echo "smoke: ok"
