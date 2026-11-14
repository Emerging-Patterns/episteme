# episteme

Summary-less RAG in Bend 2: retrieval returns verbatim, cited source paragraphs. No embeddings, and no generated text in retrieval.

Books, Claude Code transcripts, Honcho chats, git history and an intent file go into one append-only log, packed into frozen shards (one source per shard). For a question, small local reader models pick the paragraphs that bear on it, and episteme returns them in time order. Readers only name paragraphs; they never write.
The gate is `nix flake check`; what episteme guarantees is in `laws/`, one file per guarantee.

```
episteme ingest books <corpus>...   # book:<corpus>/<book>
episteme ingest claude              # chat:claude/<project>, from ~/.claude/projects
episteme ingest honcho              # chat:honcho
episteme ingest git                 # git:<repo dir>
episteme ingest intent              # intent, from $EPISTEME_HOME/intent.md
episteme ingest --all               # claude, git, intent, honcho
episteme ingest                     # pack log batches the shards lack
episteme ingest --reshard
episteme sources
episteme show <record id>[#<n>]
episteme ask --filter <sources> [--since <date>] [--author <names>] "<question>"
episteme eval <questions.jsonl> --label <name>
episteme serve [--host 127.0.0.1] [--port 18113]
```

Build with `nix build`. Data lives under `$EPISTEME_HOME` (default `~/.local/share/episteme`); `config.json` there sets the shard size and the reader pool. Ingest holds `$EPISTEME_HOME/lock` (a second ingest refuses); `ask` and `sources` never write, and refuse with "run episteme ingest" when the shards are behind the log. Honcho is read from `$HONCHO_BASE_URL` with `$HONCHO_API_KEY`.

Every question (`ask`, `serve` or `eval`) appends one JSON line to `$EPISTEME_HOME/telemetry.jsonl`: the question, its filter, how long it took, the size of each source it hit, and each shard's size in and excerpts out (laws/TelemetryLineOfARun.bend).

## Readers

A reader is any HTTP server that answers `GET /health` and an OpenAI-style `POST /v1/chat/completions` for one shard with `{"ids": ["p3", ...]}`, the labels of the paragraphs that bear on the question; `config.json`'s `pool` lists them with a number of parallel slots each. Before a question's reads, `ask` posts the run's shard names, and the authors the question names with `--author`, to `POST /v1/episteme/run`; a reader may ignore it, or rank the whole run and answer `{"ranked": true}`, and is then read by name (`POST /v1/episteme/read`) instead of being sent each shard.

- `deploy/f2/` is the default reader: BM25 fused with attention read out of Qwen3.5-0.8B (layers 0 to 11), ranking a question's whole run and filling one token budget. It needs one CUDA GPU with about 10 GB; see its `f2serve.py` header for setup.
- `deploy/reader.sh` runs llama-server with any instruction model as a generating reader.

`episteme serve` serves `ask`, `show` and `sources` as MCP tools over streamable HTTP at `/mcp` (on ezmcp); a refusal is a tool error, never an exit. It does no authorization: bind 127.0.0.1 unless a proxy that authenticates sits in front.

`skill/SKILL.md` tells agents when and how to ask; install it with `ln -s <this repo>/skill ~/.claude/skills/episteme`.
