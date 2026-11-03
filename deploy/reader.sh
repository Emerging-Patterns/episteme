#!/usr/bin/env bash
# Run one llama-server reader instance in the foreground, bound to
# 127.0.0.1, with any instruction model. Per-slot ctx should be about
# 2 * shard_tokens (32768 for 16k shards): chat text tokenizes at 1.7 to 2.66
# characters a token, so a shard plus at most 6 tokens per paragraph, 64 of
# output and 512 of thinking fits. --reasoning-budget 512 caps a thinking
# model's thinking to what src/read.bend Read.max_tokens allows for.
# --cache-ram 8192 keeps shard prefixes in host RAM across slots, so a
# repeat question re-reads almost no prompt tokens. LLAMA_SERVER names the
# binary (default: llama-server on PATH).
# usage: reader.sh <gpu> <port> <model.gguf> <ctx> <slots>
set -euo pipefail
[ $# -eq 5 ] || { echo "usage: $0 <gpu> <port> <model.gguf> <ctx> <slots>" >&2; exit 2; }
gpu=$1 port=$2 model=$3 ctx=$4 slots=$5
for n in "$gpu" "$port" "$ctx" "$slots"; do
  [[ $n =~ ^[0-9]+$ ]] || { echo "gpu, port, ctx and slots must be all digits: '$n'" >&2; exit 2; }
done
CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=$gpu exec "${LLAMA_SERVER:-llama-server}" \
  -m "$model" -ngl 99 -c $((ctx * slots)) -np "$slots" -fa on --jinja \
  --host 127.0.0.1 --port "$port" --metrics --cache-ram 8192 --reasoning-budget 512
