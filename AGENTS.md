# AGENTS.md

How to work in this repository. It is written for coding agents, and it holds for people too.

## What episteme is

episteme answers a question from the raw record: one append-only log of records, packed into frozen shards that small local reader models scan, returning verbatim excerpts. Each shard holds one source, `<kind>:<name>`, as the records a caller gives with `episteme ingest records` name it; episteme reads no source itself. The log is never rewritten: a record is changed by a later record with its id and removed by a later removal of its id (laws/LiveKeepsLastVersion.bend), and its source's shards are then packed again, a changed record where its earlier version was (laws/ChangedRecordKeepsItsPlace.bend). What episteme guarantees is one file per guarantee under `laws/`; `LAWS.bend`'s header says how they are laid out, and what is trusted rather than proved is said on the code (`# Trusted, not proved:`).

## Build and check

```bash
nix flake check                                      # the gate: proofs and lint
nix develop -c ez lock                               # must leave ez.lock.toml unchanged unless you meant to change it
nix develop -c ez prove                              # every PROOF.bend in the tree
nix develop -c ez tool run bolt check --RTS +RTS --gpu off -RTS   # lint: clean
```

Flakes see only files git tracks: `git add` a new file before `nix flake check`. The proof pass line is exactly `ALL PROOFS CHECK`; bolt must report 0 errors.

## Rules

- **Proofs, not tests.** New behavior is a guarantee in its own `laws/<Name>.bend`, its prose on top and its quantified laws under it (laws need a binder: `for x: T`), proved in `proofs/<Name>.bend`; `LAWS.bend` and `PROOF.bend` only import them. Definitions several law files share go in `laws/defs/`, lemmas several proofs share in `proofs/lemmas/`. Break each new law once to see the gate catch it, then restore it.
- **Spec first.** Law file (prose, then laws), then code. Agents write the law files. Any change to an existing law file's prose or laws (wording, or proved to trusted) goes to the maintainer first.
- **Pure core, thin IO.** Every decision is a pure function under `src/` that `LAWS.bend` can reach; IO (files, HTTP, git) only runs what the core decided.
- **Trust dependency proofs.** Dependents cite a dependency's proved guarantees, its law files; never prove its internals.
- **Never publish to the hub**, not even to test: no real `ez publish` or `bend --publish`. Push only what the maintainer asks to push.
- **Never lower bolt levels** or add suppressions to get green.
- **Ground on the fleet's current origin/main** (ezsys, ezhttp, ezjson, shake, bolt), not the `ez` on PATH, `~/.bend/current` or cached skills. Bend is 2.0.38, pinned in `flake.nix`; run everything through `nix develop -c`.
- **Generic records only.** No source-specific code: what a kind of source becomes as records is its caller's, piped in with `episteme ingest records`. Law prose names no source kinds.
- **Keep it simple.** Every addition must earn its place by a measured result; the default answer to a new mechanism is no. Readers output labels only, never text. No summaries anywhere. No embeddings.
- **No corpus or chat text in the repo**, the skill included, and nothing about one person's deployment (hosts, GPUs, paths, services). Data lives under `EPISTEME_HOME`.
- **Readers.** A reader answers `/health` and `/v1/chat/completions` per shard with labels only (laws/RequestAdmitsOnlyLabels.bend), and may use the run notice `POST /v1/episteme/run` (laws/RunNoticeNamesShards.bend); one that answers it `"ranked": true` is then read by name with `POST /v1/episteme/read` (laws/RankedReadNamesShard.bend), unless its answer also told the run's reads, `"reads": [...]`, one for each shard named (laws/NoticeAnswerTellsReads.bend). A reader may give each label its rank, and `ask` prints the best ranked that fit the budget and keeps all of it in run files (laws/BestRankedArePrinted.bend). `deploy/f2/` is the default reader; `deploy/reader.sh` starts a llama-server one. Stop a reader by PID after checking `/proc/<pid>/cmdline`, never with `pkill -f`.
- **Sizes.** Ingested paragraphs never exceed `PARA_MAX = 4000` characters (`Para.max()`); shard size must be at least `2 * PARA_MAX` characters.

## Docs

- No em dashes anywhere.
- The README stays short.

## Commits and pull requests

- Commit subjects and PR titles use [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
- End each commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- One change per commit or PR. Merge only when the gate is green.
