# episteme

Summary-less RAG, in Bend 2. Retrieval returns the record's own paragraphs, verbatim and cited, never a summary: no chunk summaries at ingest, no embeddings, no generated text anywhere in the retrieval path. The model answering the question reads the original words and cites them.

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
episteme ask --filter <sources> [--since <date>] "<question>"
episteme eval <questions.jsonl> --label <name>
```

Build with `nix build`. Data lives under `$EPISTEME_HOME` (default `~/.local/share/episteme`); `config.json` there sets the shard size and the reader pool. Ingest holds `$EPISTEME_HOME/lock` (a second ingest refuses); `ask` and `sources` never write, and refuse with "run episteme ingest" when the shards are behind the log. Honcho is read from `$HONCHO_BASE_URL` with `$HONCHO_API_KEY`.

## Readers

A reader is any HTTP server that answers `GET /health` and an OpenAI-style `POST /v1/chat/completions` for one shard with `{"ids": ["p3", ...]}`, the labels of the paragraphs that bear on the question; `config.json`'s `pool` lists them with a number of parallel slots each. Before a question's reads, `ask` posts the run's shard names to `POST /v1/episteme/run`; a reader may ignore it.

- `deploy/f2/` is the default reader: BM25 fused with attention read out of Qwen3.5-0.8B (layers 0 to 11), ranking a question's whole run and filling one token budget. It needs one CUDA GPU with about 10 GB; see its `f2serve.py` header for setup.
- `deploy/reader.sh` runs llama-server with any instruction model as a generating reader.

`skill/SKILL.md` tells agents when and how to ask; install it with `ln -s <this repo>/skill ~/.claude/skills/episteme`.
