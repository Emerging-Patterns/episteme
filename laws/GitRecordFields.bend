# `Git.record(name, path, Commit{hash, secs, author, msg, files})` is
# `Record.make("git:" ++ name ++ "@" ++ hash, Git.utc(secs), "git:" ++ name,
# author, "", "", Git.body(msg, files), "git:" ++ path ++ "@" ++ hash)`, and
# every record of `Git.records(name, path, cs)` has source `git:<name>`, no
# thread and no parent.
#
# `src/git.bend` decides what a commit of `git log` becomes. The connector
# asks git for each commit, oldest first, as NUL (U+0000, which no commit
# message can hold), then its hash, its author time in seconds since 1970
# (`%at`), its author name and its raw message, each followed by U+001F, then
# its `--numstat` lines (`Git.args`). `Git.read(text)` cuts the text at each
# NUL and reads each piece as `Commit{hash, secs, author, msg, files}`: the
# first three fields, the last field's non-blank lines as the numstat lines,
# and every field between as the message, joined again by U+001F, so a message
# holding U+001F or U+001E survives. A piece with fewer than five fields or a
# time that is not a number (a date before 1970) is no commit: when it is not
# blank it is a bad piece, which the connector names on stderr; the blank text
# before the first NUL is nothing. `Git.record(name, path, c)` is
# `Record.make` of the id `git:<name>@<hash>`, the author time as ISO 8601 UTC
# (`Git.utc`, ezsys's `time.iso` with 0 milliseconds, trusted below), the
# source `git:<name>`, the author, no thread or parent, the body
# `Git.body(msg, files)` and the pointer `git:<path>@<hash>`, which `episteme
# show` resolves with `git show` (main.bend); a commit whose body has no
# paragraph makes no record. `Git.body` is the message, then, when there are
# numstat lines, a blank line, `files:` and the lines `Git.cut(files,
# Git.files.max())` keeps, one a line, then `Git.more` of the lines it
# dropped: `<k> more files` when it dropped `k`, else nothing. `Git.cut` keeps
# lines from the first while each, with its line feed, fits in what is left of
# `Git.files.max()` (20,000) code points, and drops every line from the first
# that does not: a commit that touches thousands of files stays one record
# that fits in a shard of the default size; a long message is not cut. The
# cursor holds one `<tip> <tip>...\t<repo path>` line per repo read
# (`Git.cursor`, `Git.cursor.text`): the tips read there, every commit they
# reach read. A line of one hash, as the first cursors wrote, is one tip. A
# read takes `Git.args(path, tips)`: the commits `HEAD` reaches and no tip
# does (`HEAD ^<tip>...`), with `--ignore-missing`, so a tip that is no longer
# a commit of the repo is ignored. Closed examples check a log text read to
# its commits and bad pieces, a commit's record, a cut, the UTC times, a
# read's arguments and the cursor text read back; no guarantee rests on them.
#
# Trusted, not proved: ezsys v0.1.0's `time.iso(secs, ms)` writes
# `YYYY-MM-DDTHH:MM:SS.mmmZ`: exactly 24 characters of that form, the date of
# day `secs / 86400` and the time of day from `secs % 86400`.
#
# Why it is trusted: Proved by ezsys's own gate (its
# laws/IsoHasFixedShape.bend and laws/IsoWritesDayAndClock.bend); that each
# day number is the right Gregorian date is its
# laws/IsoWritesGregorianDate.bend, pending there and checked by its
# laws/LeapAndCenturyRulesHold.bend and laws/InputBoundariesDated.bend and by
# `git_utc_example` (laws/GitTimesAreUtc.bend). episteme cites them and never
# re-proves them.
import Base
import ../src/record.bend as R
import ../src/git.bend as G
import ./defs/ListMembership.bend as D1

# LAW: a commit is the record of git:<name>@<hash>, its author time in
# UTC, source git:<name>, its author, no thread or parent, its body and the
# pointer git:<path>@<hash>
law git_record:
  for name: String
  for path: String
  for hash: String
  for secs: U32
  for author: String
  for msg: String
  for files: List<&2, String>
  {G.Git.record(name, path, G.Commit{hash, secs, author, msg, files})
    == R.Record.make("git:" ++ name ++ "@" ++ hash, G.Git.utc(secs), "git:" ++ name,
      author, "", "", G.Git.body(msg, files), "git:" ++ path ++ "@" ++ hash)
    : Maybe<&2, R.Record>}

# what a git record carries: its source, thread and parent
def git.stamp(record: R.Record) -> String & String & String:
  match record:
    case R.Record{_id, _ts, source, _author, thread, parent, _paras, _ptr}:
      (source, thread, parent)

# LAW: every record of a repo's commits is from git:<name>, with no thread
# and no parent
law git_stamp:
  for name: String
  for path: String
  for cs: List<&2, G.Commit>
  for r: R.Record
  for h: D1.Elem(R.Record, r, G.Git.records(name, path, cs))
  {git.stamp(r) == ("git:" ++ name, "", "") : String & String & String}
