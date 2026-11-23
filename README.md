# episteme

Summary-less RAG in Bend 2: retrieval returns verbatim, cited source paragraphs. No embeddings, and no generated text in retrieval.

Records a caller gives as JSON lines go into one append-only log, packed into frozen shards (one source per shard). For a question, small local reader models pick the paragraphs that bear on it, and episteme returns them in time order. Readers only name paragraphs; they never write.
The gate is `nix flake check`; what episteme guarantees is in `laws/`, one file per guarantee.

```
episteme ingest records <file|-> [--complete]   # records given as JSON lines
episteme ingest                     # pack log batches the shards lack
episteme ingest --reshard
episteme sources
episteme show <record id>[#<n>]     # or runs/<run>/<file>, a run file
episteme ask --filter <sources> [--since <date>] [--author <names>] "<question>"
episteme eval <questions.jsonl> --label <name>
episteme serve [--host 127.0.0.1] [--port 18113]
```

Build with `nix build`. Data lives under `$EPISTEME_HOME` (default `~/.local/share/episteme`); `config.json` there sets the shard size, the reader pool and, optionally, `refuse`: `[[selector, message], ...]`, filters too wide to ask, each refused with its message, along with any prefix that selects all it does (laws/FilterRefusesCoveredSelectors.bend). Ingest holds `$EPISTEME_HOME/lock` (a second ingest refuses with exit 75); `ask` and `sources` never write, and refuse with "run episteme ingest" when the shards are behind the log. A record's id names its last version: a changed record is stored after a removal of its id, a removed one as a removal alone, and its source is then packed again, so `ask` and `show` give only the current version, a changed record where its earlier version was (laws/LiveKeepsLastVersion.bend, laws/ChangedRecordKeepsItsPlace.bend, laws/SourceShardsHoldCurrentRecords.bend).

## Records as JSON lines

`episteme ingest records <file>` (`-` reads standard input) stores records a caller builds: episteme reads no source itself, so what a book, a chat or a repo becomes as records is the caller's. Each non-empty line is one record as the log stores it:

```
{"id": "<source>@<key>", "ts": "YYYY-MM-DDTHH:MM:SS.mmmZ", "source": "<kind>:<name>",
 "author": "", "thread": "", "parent": "", "ptr": "", "text": "..."}
```

`id`, `ts` (ISO 8601 UTC, string order is time order) and `source` are required, non-empty strings; `author`, `thread`, `parent` and `ptr` are optional strings, `""` when left out (`ptr` is what `show` resolves; `"removed"` is refused). The body is exactly one of `text`, split into paragraphs numbered from 1 with offsets from 0, or `paras`, the stored form `[[n, start, end, "text"], ...]` with its offsets as given. Every record must have a paragraph. A line that is no such record refuses the whole run, exit 1, before anything is appended. Against the current records of its source: a record identical to the current one with its id appends nothing, a new id is appended, and a changed one is appended after a removal of its id; the last line of an id counts. With `--complete` the input is the whole of each source it names, and every current record of those sources whose id it lacks is removed; without it nothing is removed. No cursor is kept: the store says what is current (laws/RecordsInputChanges.bend). `show` reads only the shards of the source an id names when the id is `<source>@<key>` with no `@` in the key.

Every question (`ask`, `serve` or `eval`) appends one JSON line to `$EPISTEME_HOME/telemetry.jsonl`: the question, its filter, how long it took, the size of each source it hit, each shard's size in and excerpts out, and which paragraphs it returned (laws/TelemetryLineOfARun.bend).

## Readers

A reader is any HTTP server that answers `GET /health` and an OpenAI-style `POST /v1/chat/completions` for one shard with `{"ids": ["p3", ...]}`, the labels of the paragraphs that bear on the question; `config.json`'s `pool` lists them with a number of parallel slots each. Before a question's reads, `ask` posts the run's shard names, and the authors the question names with `--author`, to `POST /v1/episteme/run`; a reader may ignore it, or rank the whole run and answer `{"ranked": true}`, and is then read by name (`POST /v1/episteme/read`) instead of being sent each shard. It may tell the reads in that answer too, `"reads": [...]`, one string for each shard the notice named, in order, each what the shard's read would hold as its content (`{"ids": [...], "ranks": [...]}`); `ask` then takes them and asks it for no shard (laws/NoticeAnswerTellsReads.bend). All of them or none: an answer with more or fewer than the run's shards tells nothing.

A reader that ranks may name more than a question prints, with each label's rank beside it: `{"ids": [...], "ranks": [...]}`, 1 the best of the run. `ask` prints the best ranked that fit `config.json`'s `budget_tokens` and, when that is not all of it, writes everything the readers named to `$EPISTEME_HOME/runs/<time>/`, one file per source in time order, the next best after what was printed as pages of one budget each (`page-2.md` and on, laws/NextBestAreInPages.bend) and `INDEX.md`, and says where, so whoever asked can sift the rest (laws/BestRankedArePrinted.bend). `episteme show runs/<run>/<file>` prints one of those files, the `show` tool too, so they can be read where the directory cannot (laws/ShowReadsRunFiles.bend). That depth costs every question the reading of each shard a deeper paragraph lies in, so a caller that will read only what is printed says so: `episteme ask --depth <tokens>` puts the run's depth in the notice, a reader that ranks takes no more for the run than that, and with a depth no greater than `budget_tokens` nothing is left to write; `config.json`'s optional `depth_tokens` says it for every question that does not (laws/DepthLimitsARankedRun.bend). Nothing prunes `runs/`. A reader that gives no ranks is printed whole when it fits and only written to the files when it does not.

A store that records the sessions that question it comes to hold its own questions: the command that asked one, a script that lists it. Before ranking, `ask` passes over every paragraph a reader named that holds the question itself, eight words or more of it, all in order, whatever the case and the signs between them; such a paragraph is not printed or written to the run files, and its place goes to the next ranked (laws/AskingsArePassedOver.bend). A question under eight words is held by no paragraph.

- `deploy/f2/` is the default reader: BM25 fused with attention read out of Qwen3.5-0.8B (layers 0 to 11), ranking a question's whole run and naming its best paragraphs up to one token budget (`BUDGET`, 32,000 tokens; set it at or under `budget_tokens` to name no more than is printed). It needs one CUDA GPU with about 10 GB; see its `f2serve.py` header for setup. It keeps a state for every shard it has read, and a first question over a large source costs the reading of those states from disk: `python deploy/f2/fit.py`, run once on a store that has shards, fits a book by which the states are kept at about a third of their bytes (`deploy/f2/joint.py`). The reader removes no state it has kept: `python deploy/f2/prune.py` removes those of shard texts the store no longer holds and those kept under an earlier book or layout, beside a running reader (`--dry` counts them).
- `deploy/reader.sh` runs llama-server with any instruction model as a generating reader.

`episteme serve` serves `ask`, `show` and `sources` as MCP tools over streamable HTTP at `/mcp` (on ezmcp); a refusal is a tool error, never an exit. It does no authorization: bind 127.0.0.1 unless a proxy that authenticates sits in front.

`skill/SKILL.md` tells agents when and how to ask; install it with `ln -s <this repo>/skill ~/.claude/skills/episteme`.
