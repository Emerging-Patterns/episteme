#!/usr/bin/env bash
# The reader pool against live llama-server instances, run by hand (the
# flake sandbox has no GPU or network). Start two readers on GPU 0 first:
#
#   deploy/reader.sh 0 18130 <model.gguf> 36864 2   # READER, a real one
#   deploy/reader.sh 0 18131 <model.gguf> 512 1     # SMALL, every call errors
#
# Then: one healthy reader beside a dead URL finishes with 0 failed and
# names the skipped URL; a budget too small for the excerpts writes them
# to run files; shards that fail on SMALL beside READER are read again on
# READER; a pool of only SMALL exits 1 with every shard listed as failed. EPISTEME names the binary (default bin/episteme).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bin=${EPISTEME:-$here/../bin/episteme}
reader=${READER:-http://127.0.0.1:18130}
small=${SMALL:-http://127.0.0.1:18131}
dead=http://127.0.0.1:9
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export EPISTEME_HOME=$work/home
export EPISTEME_BOOKS=$work/books
mkdir -p "$EPISTEME_HOME" "$EPISTEME_BOOKS/tiny/text"

fail() { echo "live: FAIL: $*" >&2; exit 1; }

for url in "$reader" "$small"; do
  curl -sf "$url/health" > /dev/null || fail "no reader at $url; start it first (see the top of this file)"
done

for book in tiny-book tiny-two; do
  for ext in txt heads.json pages.json; do
    cp "$here/fixtures/books/tiny/text/tiny-book.$ext" "$EPISTEME_BOOKS/tiny/text/$book.$ext"
  done
done
chmod -R u+w "$EPISTEME_BOOKS"

# a config of 8000-character shards and the given pool
config() {
  printf '{"shard_tokens": 100, "chars_per_token": 8000, "pool": %s, "budget_tokens": 60000}\n' \
    "$1" > "$EPISTEME_HOME/config.json"
}

config "[[\"$reader\", 2]]"
"$bin" ingest books tiny > /dev/null 2>&1
shards=$(find "$EPISTEME_HOME/shards/8000" -mindepth 2 -name '*.json' | wc -l)
[ "$shards" -ge 2 ] || fail "the fixture should make at least two shards, made $shards"
question="How many gulls did the lantern keeper count before noon?"

# one healthy reader and one dead URL: the dead one is skipped, the run ends
config "[[\"$dead\", 1], [\"$reader\", 2]]"
rc=0
"$bin" ask --filter book:tiny/ "$question" > "$work/out.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 0 ] || fail "ask with a dead instance exited $rc: $(cat "$work/err.txt") $(tail -n 5 "$work/out.txt")"
grep -q "^skipping $dead: " "$work/err.txt" || fail "stderr does not name the skipped URL: $(cat "$work/err.txt")"
grep -q "^shards: $shards read, 0 failed$" "$work/out.txt" || fail "the footer is not $shards read, 0 failed: $(tail -n 5 "$work/out.txt")"
grep -q 'seven gulls' "$work/out.txt" || fail "no excerpt names the seven gulls: $(cat "$work/out.txt")"
echo "live: dead instance skipped, $shards shards read, 0 failed"

# a budget too small for the excerpts: they go to run files, one per source
config "[[\"$reader\", 2]]"
sed -i 's/"budget_tokens": 60000/"budget_tokens": 1/' "$EPISTEME_HOME/config.json"
"$bin" ask --filter book:tiny/ "$question" > "$work/out.txt" 2> "$work/err.txt" || fail "ask over budget failed: $(cat "$work/err.txt")"
run=$(head -n 1 "$work/out.txt")
[ -f "$run/INDEX.md" ] || fail "no INDEX.md under $run: $(cat "$work/out.txt")"
grep -q '^book:tiny_tiny-book.md book:tiny/tiny-book [0-9]' "$run/INDEX.md" || fail "INDEX.md: $(cat "$run/INDEX.md")"
grep -q 'seven gulls' "$run/book:tiny_tiny-book.md" || fail "the run file lacks the gulls"
grep -q '^shards: [0-9]* read, 0 failed$' "$work/out.txt" || fail "no footer after the run path"
echo "live: over budget, excerpts written under $run"

# a pool where one instance fails every call: its shards are read again
# on the other instance, so the run ends with 0 failed
config "[[\"$small\", 1], [\"$reader\", 2]]"
rc=0
"$bin" ask --filter book:tiny/ "$question" > "$work/out.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 0 ] || fail "ask with one failing instance exited $rc: $(tail -n 8 "$work/out.txt")"
grep -q "^shards: $shards read, 0 failed$" "$work/out.txt" || fail "the failing instance's shards were not read again: $(tail -n 8 "$work/out.txt")"
echo "live: one instance failing every call, its shards read again on the other, 0 failed"

# a pool whose every call errors: exit 1, every shard failed, none NONE
config "[[\"$small\", 1]]"
rc=0
"$bin" ask --filter book:tiny/ "$question" > "$work/out.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 1 ] || fail "ask with every call failing exited $rc, not 1: $(cat "$work/err.txt")"
grep -q "^shards: $shards read, $shards failed$" "$work/out.txt" || fail "the footer is not $shards read, $shards failed: $(tail -n 5 "$work/out.txt")"
[ "$(grep -c '^failed shard ' "$work/out.txt")" = "$shards" ] || fail "not every shard is listed as failed: $(cat "$work/out.txt")"
grep -q '^### ' "$work/out.txt" && fail "a failed run printed excerpts"
echo "live: every call failed, exit 1, $shards of $shards shards listed as failed"

echo "live: ok"
