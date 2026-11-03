---
name: episteme
description: Answer from the primary record with verbatim, cited excerpts. Use when a question turns on what an ingested book actually says, what was decided or said in an earlier Claude Code session or Honcho chat, why a repo changed (its git history), or what the user says they mean to do (their intent file). Triggers include "what did we decide about X", "when did we change Y and why", "find where the book says Z", "what did I say about W". Not for questions the current repo or conversation already answers.
---

# episteme

episteme reads the user's raw record and returns verbatim excerpts, in time order. Small local reader models pick which paragraphs bear on the question; they never write text, and nothing is summarized. You read the excerpts and answer.

Run it as `episteme <command>` (or `nix run <path to the episteme repo> -- <command>`).

## Sources

Every record has one source:

| Source | What it holds |
| :---- | :---- |
| `book:<corpus>/<book>` | a book, one record per section (`book:<corpus>/` for a whole corpus) |
| `chat:claude/<project>` | Claude Code transcripts of one project; `<project>` is the `~/.claude/projects` dir name without its leading `-`, e.g. `chat:claude/home-alice-projects-site` |
| `chat:honcho` | Honcho's raw messages |
| `git:<repo dir>` | one repo's commits, e.g. `git:episteme` |
| `intent` | the user's intent file, one record per version |

`episteme sources` lists every source with its records, paragraphs and shards. Run it when unsure what to filter on.

In `chat:claude`, the author `noah` is only the user's own typed lines. Other authors are `agent`, `tool` (a tool result), `task-notification`, `meta`, `channel`, `peer`, or the model's name.

## Asking

```
episteme ask --filter <sources> [--since <YYYY-MM-DD | YYYY-MM-DDTHH:MM:SS.mmmZ>] "<question>"
```

- **Always pass a narrow `--filter`.** It takes exact sources and prefixes ending in `/`, comma-separated: `--filter book:<corpus>/`, `--filter chat:claude/<project>,git:<repo>`. A missing filter, or one over every chat (`chat:claude/`, `chat:`), is refused.
- **Cost is the shards read.** A reader scans every shard the filter hits; a shard it has not seen before takes about a second, and a big chat project is hundreds of shards. Pick the fewest sources that can hold the answer; `episteme sources` shows how many shards each has.
- **For chats or git about recent work, pass `--since`** (UTC). It reads only shards holding a record at or after that time and drops older excerpts, which often cuts a chat project by half or more. It is for chat and git only: book excerpts carry no real date (a book without a year in its id is dated by its ingest time).
- Ask one question at a time, in plain words; put the names and terms the record would use into it.

## Reading the output

Each excerpt is a header line `### <record id> | <source> | <ts> | <author>`, then one line `<record id>#<n>: <text>` per paragraph. A large result goes to files under `$EPISTEME_HOME/runs/<time>/` (one `<source>.md` each, and `INDEX.md`), and ask prints that directory.

- **Cite every claim** as `<record id>#<n>`. Make no claim the excerpts do not hold.
- **Later excerpts are the current state.** When two disagree, the later one is what holds now; say what changed.
- `episteme show <record id>` prints the whole record, `episteme show <record id>#<n>` one paragraph. A tool result or a long tool input is a pointer, and show prints the file line or git patch it points at.

## Failures

The footer reads `shards: <n> read, <k> failed`, then `failed <source> shard <n> at <url>: <why>` per failed shard. A failed shard was not read: **report it with your answer, and never treat its gap as "the record says nothing"**. Exit 1 means some shard failed.

Exit 2 with `skipping <url>: ...` means no reader is up. Tell the user rather than starting one.

## Keeping it fresh

`episteme ingest --all` adds what is new from claude, git, the intent file and Honcho. Books take corpus names: `episteme ingest books <corpus>...`. Reads never write: when the shards are behind the log, `ask` and `sources` exit 1 and say to run `episteme ingest`, which packs them. One ingest runs at a time: it holds `$EPISTEME_HOME/lock`, and a second one exits 1 naming it; remove the lock by hand only when no ingest is running.
