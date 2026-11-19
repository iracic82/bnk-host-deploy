#!/usr/bin/env bash
# lab gpus: the three simulated GPUs, read from each model server's own vLLM metrics.
source "$(dirname "$0")/../lib.sh"
curl -s -m 20 "http://127.0.0.1:${PORT_INFERENCE}/api/state" | jq -r '
  if (.gpus | length) == 0 then "no model servers yet (challenge 12, step 3)" else
  (["GPU","pod","node","requests","KV-cache hit rate","cached/prompt tokens"] | @tsv),
  (.gpus | to_entries[] | [(["A","B","C","D","E"][.key]), .value.name, .value.node, (.value.requests // 0 | tostring),
     ((((.value.hit_rate // 0) * 100) | round | tostring) + "%"), "\(.value.cached_tokens // 0)/\(.value.prompt_tokens // 0)"] | @tsv) end' | column -t -s $'\t'
