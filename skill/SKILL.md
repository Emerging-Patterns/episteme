---
name: episteme
description: Answer from the primary record with verbatim, cited excerpts. Use when a question turns on what an ingested source actually says: a book, an earlier chat or session, a repo's history, notes, or any other records stored in episteme. Triggers include "what did we decide about X", "when did we change Y and why", "find where the book says Z", "what did I say about W", and "which design principles apply to this code" over a corpus of design books. Not for questions the current repo or conversation already answers.
---

# episteme

episteme reads the user's raw record and returns verbatim excerpts, in time order. Small local reader models pick which paragraphs bear on the question; they never write text, and nothing is summarized. You read the excerpts and answer.

Run it as `episteme <command>` (or `nix run <path to the episteme repo> -- <command>`).

When the `episteme` MCP tools are loaded (`ask`, `show`, `sources`, served by `episteme serve`), call them instead: `ask` takes `question`, `filter` (the `--filter` value) and an optional `since` and `author`, `show` takes `id`. Everything below holds for them too; a refusal comes back as a tool error.

## Sources

Every record has one source, `<kind>:<name>`, as whoever ingested it named it (for example `book:<corpus>/<book>` or `chat:<app>/<project>`). `episteme sources` lists every source with its records, paragraphs and shards: run it when unsure what to filter on. Which sources exist, and what their authors and ids mean, is said by the setup that feeds them, not by episteme.

Every record has an author, shown last in an excerpt's header, as its source writes it, so `--author` takes the name as that source writes it, and one question over two kinds of source may name the same person twice: `--author "<name in one>,<name in the other>"`. A changed record shows only its latest version, a removed one none.

## Asking

```
episteme ask --filter <sources> [--since <YYYY-MM-DD | YYYY-MM-DDTHH:MM:SS.mmmZ>] [--author <names>] "<question>"
```

- **Always pass a narrow `--filter`.** It takes exact sources and prefixes ending in `/`, comma-separated: `--filter book:<corpus>/`, `--filter <kind>:<name>,<kind>:<prefix>/`. A missing filter is refused, and so is one the setup refuses as too wide (the refusal says what to name instead).
- **Cost is the shards read.** A reader scans every shard the filter hits; a shard it has not seen before takes about a second, and a big chat project is hundreds of shards. Pick the fewest sources that can hold the answer; `episteme sources` shows how many shards each has.
- **For recent work, pass `--since`** (UTC). It reads only shards holding a record at or after that time and drops older excerpts, which often cuts a chat project by half or more. It is only as good as the sources' timestamps: a source whose records carry no real date (a book) is not narrowed by it.
- **For what one speaker said, pass `--author`** (the tool's `author`), with the user's name as the source writes it for the user's own lines. Only excerpts by the named authors come back (comma-separated, as the excerpt headers show them), and the reader spends its whole budget on their paragraphs, taking only those the question bears on. No excerpts means nothing of theirs was found on it in those sources; a short reply that only makes sense in its context can be missed, so report "nothing found", not "never said". Without it, a question like "what did the user say about X" is answered mostly with what the assistant said about X: the user's lines are under a hundredth of a transcript. Put the topic in the question, not the speaker.
- **The session you are in may not be in the record yet.** Whatever feeds chats in runs when it runs, so what was said minutes ago is found in your own context, not by asking.
- Ask one question at a time, in plain words; put the names and terms the record would use into it.
- **An earlier asking of your question is not returned.** A paragraph that holds the whole question, eight words or more, in order (the command that asked it before, a script that lists it) is passed over, so asking again brings the same evidence, not the earlier askings. To find when something was asked, ask about it in other words or with fewer than eight.

## Principles for code

To ground a design or refactor in a corpus of design books, ask in two passes:

1. **Describe the code, don't paste it.** Say its shape in the words a design book would use: what it stores, which combinations cannot happen, what every caller has to check. A raw snippet matches the books' code samples on tokens like `bool` and `int`, not the prose that states a principle.
2. **Ask broadly** over the corpus (`--filter book:<corpus>/`): "Which design principles apply to <the description>?" Note the principles that recur and which book each comes from.
3. **Follow up narrowly** on one principle, filtered to that one book (`--filter book:<corpus>/<book>`): how to apply it, where its author says it does not apply, what it costs. The limits often come only in this pass.
4. **Weigh it against the code.** Two books can point opposite ways (split a module, or keep what shares one piece of knowledge together); the excerpts give the arguments, the code decides. Cite the passages behind the choice.

Excerpts come in record order, not by relevance, so read the whole result before picking.

## Reading the output

Each thing is said once. A line `## <source>` names the source of the excerpts under it, until the next such line. Each excerpt is a header line `### <record id> | <ts> | <author>`, then one line `#<n>: <text>` per paragraph: a paragraph's citation is its header's record id and its own number, `<record id>#<n>`.

**What is printed is the best ranked, not all that was found.** When the readers named more than fits, the excerpts end with a line naming a directory under `$EPISTEME_HOME/runs/<time>/` that holds all of it: `page-2.md`, `page-3.md` and on, the next best after what was printed, in its format, each about as much again and best first; one `<source>.md` per source, in time order, made for searching (every header names its source and every paragraph line starts with its whole citation, `<record id>#<n>:`); and `INDEX.md` listing them. When the printed excerpts do not answer the question, or it asks for everything on a subject, read the next page before asking again, or search the source files for the names and terms you need and read around the hits. All of it is several times what was printed, so do not read it whole. `episteme show runs/<time>/<file>` (the `show` tool with that as its `id`) prints one of those files, for when the directory itself cannot be read.

- **Cite every claim** as `<record id>#<n>`. Make no claim the excerpts do not hold.
- **Later excerpts are the current state.** When two disagree, the later one is what holds now; say what changed.
- `episteme show <record id>` prints the whole record, `episteme show <record id>#<n>` one paragraph. A record whose body is a pointer (`file:<path>:<line>` or `git:<repo>@<hash>`) is shown with the file line or git patch it points at.

## Failures

The footer reads `shards: <n> read, <k> failed`, then `failed <source> shard <n> at <url>: <why>` per failed shard. A failed shard was not read: **report it with your answer, and never treat its gap as "the record says nothing"**. Exit 1 means some shard failed.

Exit 2 with `skipping <url>: ...` means no reader is up. Tell the user rather than starting one.

## Keeping it fresh

Records come in as JSON lines: `episteme ingest records <file|-> [--complete]`, run by whatever feeds each source. Reads never write: when the shards are behind the log, `ask` and `sources` exit 1 and say to run `episteme ingest`, which packs them. One ingest runs at a time: it holds `$EPISTEME_HOME/lock`, and a second one exits 75 naming it (try again later); remove the lock by hand only when no ingest is running.
