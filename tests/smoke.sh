#!/usr/bin/env bash
# The IO shell end to end on synthetic records given as JSON lines: ingest,
# shards split by source, sources, show, a run with nothing new, a crash
# between the batch and the shards (reads refuse, a bare ingest packs), a
# crash between a source's shards and the covered mark, a lost tail, a
# stale shard size, a crash in the middle of a run, the ingest lock (a
# second ingest refused, the lock removed after a failed one), ask (with
# and without --since), its telemetry line and eval without readers, and
# changes and removals (a changed record keeps its place). Each ingest case ends with no id twice in the log,
# but the records', whose changes reuse ids, and
# shards byte for byte as a reshard writes them. EPISTEME
# names the binary (default bin/episteme, built with
# `bend main.bend -o bin/episteme`).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bin=${EPISTEME:-$here/../bin/episteme}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export EPISTEME_HOME=$work/home
mkdir -p "$EPISTEME_HOME" "$work/rec"
log=$EPISTEME_HOME/log

fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

# a corpus: the records of the fixture book (tests/fixtures/records, a book
# cut at its headings, offsets into the whole file) under one or more
# names, as $work/rec/<name>.jsonl
corpus() {
  local name=$1; shift
  : > "$work/rec/$name.jsonl"
  for book in "$@"; do
    sed "s#book:tiny/tiny-book#book:$name/$book#g; s#\"author\":\"tiny-book\"#\"author\":\"$book\"#" \
      "$here/fixtures/records/tiny-book.jsonl" >> "$work/rec/$name.jsonl"
  done
}

# ingest a corpus's records
book() { "$bin" ingest records "$work/rec/$1.jsonl"; }

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

book tiny > /dev/null
[ "$(batches)" = 2 ] || fail "one log batch per source after the first ingest"
frozen=$(frozen_of "$shards")
[ -n "$frozen" ] || fail "the fixture should freeze at least one shard"
[ -f "$shards/book:tiny%2Ftiny-book/tail.json" ] || fail "no shard directory for book:tiny/tiny-book: $(ls "$shards")"
[ -f "$shards/book:tiny%2Ftiny-two/tail.json" ] || fail "no shard directory for book:tiny/tiny-two: $(ls "$shards")"
grep -q '^{"covered":2}$' "$shards/covered.json" || fail "the covered mark: $(cat "$shards/covered.json")"
one_source 8000 "first ingest"

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
book tiny > /dev/null
[ "$(batches)" = 2 ] || fail "a run with nothing new wrote a log batch"
[ -z "$(find "$EPISTEME_HOME" -type f -newer "$work/mark")" ] || fail "a run with nothing new wrote a file"
for f in $frozen; do cmp "$work/before/$f" "$shards/$f" || fail "frozen shard $f changed"; done
unique "nothing new"

# a crash after the batch and before the shards: put the shards back as
# they were; reads refuse and write nothing, and the next ingest packs the
# batch
corpus later tiny-book
book later > /dev/null
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
book later > /dev/null 2> "$work/err.txt"
grep -q 'packed log batches 3 to 3' "$work/err.txt" || fail "no catch-up: $(cat "$work/err.txt")"
[ "$(batches)" = 3 ] || fail "a re-run after a crash wrote a log batch"
diff -r "$work/after" "$shards" > /dev/null || fail "the caught-up shards differ"
unique "crash"
fresh 8000 "crash"

# a crash after a source's shards and before the covered mark: the source
# is caught up from its own tail, and its batch is not packed twice
corpus again tiny-book
book again > /dev/null
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
book third > /dev/null
book fourth > /dev/null
[ "$(batches)" = 6 ] || fail "the 8080 ingests wrote no batches"
fresh 8080 "other size"
config 100
"$bin" ingest 2> "$work/err.txt"
grep -q 'packed log batches 5 to 6' "$work/err.txt" || fail "the stale size was not caught up: $(cat "$work/err.txt")"
"$bin" sources | grep -q '^book:fourth/tiny-book ' || fail "sources lacks book:fourth/tiny-book"
unique "stale size"
fresh 8000 "stale size"

# a crash in the middle of a run (one batch per source), then a run over
# another corpus that has nothing new, then the first again: only the
# source the crash lost is added
corpus pair pair-one pair-two
cp -r "$EPISTEME_HOME" "$work/home-before-pair"
book pair > /dev/null
[ "$(batches)" = 8 ] || fail "the pair corpus wrote no batches"
rm "$log/00000008.jsonl"
rm -rf "$EPISTEME_HOME/shards"
cp -r "$work/home-before-pair/shards" "$EPISTEME_HOME/shards"
book tiny > /dev/null
[ "$(batches)" = 7 ] || fail "a run with nothing new wrote a log batch after the crash"
book pair > "$work/pair.txt"
grep -q '^book:pair/pair-one: 0 records' "$work/pair.txt" || fail "pair-one ran again: $(cat "$work/pair.txt")"
grep -q '^book:pair/pair-two: 6 records' "$work/pair.txt" || fail "pair-two was not added: $(cat "$work/pair.txt")"
[ "$(batches)" = 8 ] || fail "the pair re-run did not add one batch"
unique "crash in a run"
fresh 8000 "crash in a run"

# the lock: while it exists a second ingest refuses, naming it, writes
# nothing and leaves the lock for its holder
corpus locked tiny-book
mkdir "$EPISTEME_HOME/lock"
touch "$work/mark"
rc=0; book locked > /dev/null 2> "$work/err.txt" || rc=$?
[ "$rc" = 75 ] || fail "an ingest while the lock exists exited $rc, not 75"
grep -qF "$EPISTEME_HOME/lock exists: another ingest is running; if none is, remove it by hand" "$work/err.txt" \
  || fail "no lock refusal: $(cat "$work/err.txt")"
[ -d "$EPISTEME_HOME/lock" ] || fail "a refused ingest removed the lock"
[ -z "$(find "$EPISTEME_HOME" -type f -newer "$work/mark")" ] || fail "a refused ingest wrote a file"
rmdir "$EPISTEME_HOME/lock"

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
printf '{"shard_tokens": 100, "chars_per_token": 8000, "pool": [["http://127.0.0.1:9", 2]], "budget_tokens": 60000, "refuse": [["notes:all/", "name one notebook"]]}\n' \
  > "$EPISTEME_HOME/config.json"
rc=0; "$bin" ask --filter notes: --filter notes:all/ "q" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask over a refused prefix exited $rc, not 2"
grep -q 'name one notebook' "$work/err.txt" || fail "no configured refusal: $(cat "$work/err.txt")"
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
"$bin" ask --filter book:tiny/ --since 2999-01-01 --author "noah, agent" "q" > "$work/out.txt" || fail "ask with --author failed"
grep -q '^shards: 0 read, 0 failed$' "$work/out.txt" || fail "ask with --author over no shard read: $(cat "$work/out.txt")"
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
printf '{"id":"c1","question":"q","filter":["notes:all/"],"gold":[]}\n' > "$work/wide.jsonl"
rc=0; "$bin" eval "$work/wide.jsonl" --label wide 2> "$work/err.txt" > /dev/null || rc=$?
[ "$rc" = 2 ] || fail "eval over a refused prefix exited $rc, not 2"
grep -q '^episteme: c1: name one notebook' "$work/err.txt" || fail "no eval refusal: $(cat "$work/err.txt")"
rc=0; "$bin" ask --filter book:tiny/ "q" > "$work/out.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask with no healthy reader exited $rc, not 2"
grep -q '^skipping http://127.0.0.1:9: ' "$work/err.txt" || fail "the dead reader is not named: $(cat "$work/err.txt")"
# telemetry: that question's line is the last, refused with exit 2 and no
# reads, naming the source the filter hit and the shards it would have read;
# the eval's line says it came from eval
tele=$EPISTEME_HOME/telemetry.jsonl
line=$(tail -n 1 "$tele")
for want in '"via":"ask","question":"q","filter":["book:tiny/"],"since":null,"authors":[],' '"code":2,"refused":"' \
  '"sources":[{"source":"book:tiny/tiny-book","shards":' '"shards":[{"source":"book:tiny/tiny-book","n":1,"chars":' \
  '"ok":false,"ms":0,"labels":0,"out_paras":0,"out_chars":0}' '"excerpts":0,"out_chars":0,"returned":[]}'; do
  case $line in *"$want"*) ;; *) fail "the telemetry line lacks $want: $line" ;; esac
done
grep -qF '"via":"eval","question":"q","filter":["book:none/"],' "$tele" || fail "no eval telemetry line"
rc=0; "$bin" ask --filter book:tiny/ --since 2000-01-01T00:00:00.000Z "q" > "$work/out.txt" 2> "$work/err.txt" || rc=$?
[ "$rc" = 2 ] || fail "ask since before every record exited $rc, not 2: no shard reached the dead pool"
config 100

# records given as JSON lines: a first run, a run with nothing new, a new
# record, a changed and a removed one with --complete (show gives only the
# new version and exits 1 for the removed one, the shards hold neither old
# text), another source left alone, a refused line, standard input, and the
# lock's exit code
rec() { printf '{"id":"%s","ts":"%s","source":"%s","author":"a","text":"%s"}\n' "$@"; }
{ rec 'note:x@one' 2000-01-01T00:00:00.001Z note:x 'The lamp is lit.\n\nThe door is shut.'
  rec 'note:x@two' 2000-01-01T00:00:00.002Z note:x 'A crow on the sill.'
  printf '{"id":"note:y@k","ts":"1999-01-01T00:00:00.000Z","source":"note:y","paras":[[1,5,9,"abcd"]],"ptr":"file:%s:1"}\n' "$work/ptr.txt"
} > "$work/in1.jsonl"
echo 'pointed line' > "$work/ptr.txt"
"$bin" ingest records "$work/in1.jsonl" > "$work/recs.txt"
grep -q '^note:x: 2 records$' "$work/recs.txt" || fail "the first records run gave: $(cat "$work/recs.txt")"
grep -q '^note:y: 1 records$' "$work/recs.txt" || fail "the first records run gave: $(cat "$work/recs.txt")"
xdir=$shards/note:x
[ -f "$xdir/tail.json" ] || fail "no shards of note:x"
"$bin" show 'note:x@one#2' > "$work/out.txt" || fail "show of a given record's paragraph failed"
grep -q '^#2: The door is shut.$' "$work/out.txt" || fail "show printed: $(cat "$work/out.txt")"
[ "$(head -n 2 "$work/out.txt" | cut -d' ' -f1-2 | tr '\n' ' ')" = "## note:x ### note:x@one " ] || fail "show does not open with the source and the record: $(cat "$work/out.txt")"
"$bin" show 'note:y@k' > "$work/out.txt" || fail "show of a record with paras failed"
grep -q '^#1: abcd$' "$work/out.txt" || fail "show of paras: $(cat "$work/out.txt")"
grep -q '^pointed line$' "$work/out.txt" || fail "show did not resolve the pointer: $(cat "$work/out.txt")"
n=$(batches)
"$bin" ingest records - < "$work/in1.jsonl" > "$work/recs.txt"
[ "$(grep -c ': 0 records$' "$work/recs.txt")" = 2 ] || fail "the same records again gave: $(cat "$work/recs.txt")"
[ "$(batches)" = "$n" ] || fail "the same records again appended a batch"
{ rec 'note:x@one' 2000-01-01T00:00:00.001Z note:x 'The lamp is out.'
  rec 'note:x@three' 2000-01-01T00:00:00.003Z note:x 'The crow flies.'
} > "$work/in2.jsonl"
"$bin" ingest records --complete "$work/in2.jsonl" > "$work/recs.txt"
grep -q '^note:x: 4 records$' "$work/recs.txt" || fail "a change, a new record and a removal gave: $(cat "$work/recs.txt")"
"$bin" show 'note:x@one' > "$work/out.txt" || fail "show of a changed record failed"
grep -q '^#1: The lamp is out.$' "$work/out.txt" || fail "show of a changed record: $(cat "$work/out.txt")"
grep -q 'lamp is lit' "$work/out.txt" && fail "show of a changed record printed the old text"
rc=0; "$bin" show 'note:x@one#2' > /dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "show of a paragraph the change dropped exited $rc, not 1"
rc=0; "$bin" show 'note:x@two' > /dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "show of a removed record exited $rc, not 1"
grep -rq 'lamp is lit\|crow on the sill\|(removed)' "$xdir" && fail "the shards hold an old or removed record"
grep -q 'The crow flies' "$xdir"/*.json || fail "the shards lost the new record"
"$bin" show 'note:y@k' > /dev/null || fail "a complete run over note:x removed note:y"
[ -e "$EPISTEME_HOME/repack/8000/note:x" ] && fail "a repack left its swap directory"
[ -e "$EPISTEME_HOME/repack/8000/note:x.old" ] && fail "a repack left the old shards"
# a record changed again keeps its place, ahead of the record that follows it
rec 'note:x@one' 2000-01-01T00:00:00.001Z note:x 'The lamp is dim.' > "$work/in3.jsonl"
"$bin" ingest records "$work/in3.jsonl" > "$work/recs.txt"
grep -q '^note:x: 2 records$' "$work/recs.txt" || fail "a change alone gave: $(cat "$work/recs.txt")"
cat "$xdir"/*.json | tr -d '\n' | grep -q 'lamp is dim.*crow flies' || fail "a changed record left its place"
fresh 8000 "records"
n=$(batches)
{ rec 'note:x@four' 2000-01-01T00:00:00.004Z note:x 'Fine.'; echo '{"id":"note:x@bad","source":"note:x","text":"no ts"}'; } > "$work/bad.jsonl"
rc=0; "$bin" ingest records "$work/bad.jsonl" > /dev/null 2> "$work/err.txt" || rc=$?
[ "$rc" = 1 ] || fail "records with a bad line exited $rc, not 1"
grep -q 'line 2 is no record' "$work/err.txt" || fail "the bad line is not named: $(cat "$work/err.txt")"
[ "$(batches)" = "$n" ] || fail "records with a bad line appended a batch"
# show reads only the shards of the source an id names: with a log batch
# unreadable it still finds a record, and still says a removed one is gone
chmod 000 "$log/00000001.jsonl"
"$bin" show 'note:x@one' > "$work/out.txt" || fail "show from the source's shards failed"
grep -q '^#1: The lamp is dim.$' "$work/out.txt" || fail "show from the shards: $(cat "$work/out.txt")"
rc=0; "$bin" show 'note:x@two' > /dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "show from the shards of a removed record exited $rc, not 1"
chmod 644 "$log/00000001.jsonl"
mkdir "$EPISTEME_HOME/lock"
rc=0; "$bin" ingest records "$work/in2.jsonl" > /dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || fail "a records ingest while the lock exists exited $rc, not 75"
rmdir "$EPISTEME_HOME/lock"

echo "smoke: ok"
