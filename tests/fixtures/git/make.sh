#!/usr/bin/env bash
# Synthetic git repos for the smoke test, built under a root the caller
# gives (a temp dir): <root>/fixrepo with 3 commits, <root>/bend/nested
# with 1, <root>/plain, a directory that is no repo, and <root>/fixrepo-wt,
# a linked worktree of fixrepo (its .git is a file). Names, dates and
# messages are made up; the dates carry UTC offsets so ingest must
# normalize them. A second argument changes the repos afterwards:
#   more    a 4th commit in fixrepo
#   amend   fixrepo's last commit rewritten under a new message
#   branch  fixrepo on a new branch side, off its HEAD~1, with 1 commit
#   back    fixrepo back on main
#   prune   main's last commit rewritten again and the old one pruned,
#           so the tip the cursor names is gone
#   rs      a commit in fixrepo whose message holds U+001E
#   renest  bend/nested made again with another history, so every tip
#           the cursor names for it is gone
set -euo pipefail

root=$1
step=${2:-make}

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME='Fixture Keeper' GIT_AUTHOR_EMAIL=keeper@example.invalid
export GIT_COMMITTER_NAME='Fixture Keeper' GIT_COMMITTER_EMAIL=keeper@example.invalid

# commit everything staged in repo $1 at date $2 with message $3
commit() {
  GIT_AUTHOR_DATE=$2 GIT_COMMITTER_DATE=$2 \
    git -C "$1" -c commit.gpgsign=false commit -q --allow-empty -m "$3"
}

# a new repo at $1
init() {
  rm -rf "$1"
  mkdir -p "$1"
  git -C "$1" init -q -b main
}

# bend/nested with one commit whose message is $1
nested() {
  local repo=$root/bend/nested
  init "$repo"
  echo 'a nested note' > "$repo/note.txt"
  git -C "$repo" add note.txt
  commit "$repo" 2026-04-05T06:07:08+00:00 "$1"
}

repo=$root/fixrepo
case $step in
  make)
    init "$repo"
    printf 'The lantern keeper counted seven gulls.\n' > "$repo/lantern.txt"
    git -C "$repo" add lantern.txt
    commit "$repo" 2026-01-01T01:30:00+05:00 $'Add the lantern log\n\nThe keeper writes one line a day.'
    printf 'Eight gulls by noon.\n' >> "$repo/lantern.txt"
    printf 'gull\ngull\n' > "$repo/gulls.txt"
    git -C "$repo" add lantern.txt gulls.txt
    commit "$repo" 2026-02-03T10:00:00-08:00 'Count the gulls'
    printf '\000\001\002' > "$repo/seal.bin"
    git -C "$repo" add seal.bin
    commit "$repo" 2026-03-04T12:00:00Z 'Add the tower seal'
    nested 'Start the nested notes'
    mkdir -p "$root/plain"
    echo 'not a repo' > "$root/plain/readme.txt"
    git -C "$repo" worktree add -q -b wt "$root/fixrepo-wt"
    ;;
  more)
    printf 'Nine gulls at dusk.\n' >> "$repo/lantern.txt"
    git -C "$repo" add lantern.txt
    commit "$repo" 2026-03-05T18:00:00+01:00 'Log the dusk count'
    ;;
  amend)
    GIT_AUTHOR_DATE=2026-03-05T18:00:00+01:00 GIT_COMMITTER_DATE=2026-03-06T09:00:00+00:00 \
      git -C "$repo" -c commit.gpgsign=false commit -q --amend -m 'Log the dusk count again'
    ;;
  branch)
    git -C "$repo" checkout -q -b side HEAD~1
    printf 'A side path by the cliff.\n' > "$repo/side.txt"
    git -C "$repo" add side.txt
    commit "$repo" 2026-03-07T08:00:00+02:00 'Sketch the side path'
    ;;
  back)
    git -C "$repo" checkout -q main
    ;;
  prune)
    GIT_AUTHOR_DATE=2026-03-05T18:00:00+01:00 GIT_COMMITTER_DATE=2026-03-08T09:00:00+00:00 \
      git -C "$repo" -c commit.gpgsign=false commit -q --amend -m 'Log the dusk count once more'
    git -C "$repo" reflog expire --expire=now --all
    git -C "$repo" gc -q --prune=now
    ;;
  rs)
    commit "$repo" 2026-03-09T07:00:00+00:00 $'Mark the tide \x1e record'
    ;;
  renest)
    nested 'Start the nested notes over'
    ;;
esac
