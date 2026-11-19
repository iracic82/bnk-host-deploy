#!/usr/bin/env bash
# lab burst picker|roundrobin [n]: send the same n requests (default 48) from 12 customers through one
# VIP and print the result. The AI Inference tab shows the same run, request by request.
source "$(dirname "$0")/../lib.sh"
mode="${1:-picker}"; n="${2:-48}"
[[ "$mode" == picker || "$mode" == roundrobin ]] || fail "usage: lab burst picker|roundrobin [n]"
api="http://127.0.0.1:${PORT_INFERENCE}/api"
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "{\"mode\":\"$mode\",\"n\":$n,\"customers\":12}" "$api/burst")
[[ "$code" == 202 ]] || fail "the console refused the run (HTTP $code): another run in progress, or no model servers yet"
step "$n requests through $([[ $mode == picker ]] && echo "BNK's endpoint picker, 10.30.30.11" || echo "round robin, 10.30.30.12")"
while :; do
  r=$(curl -s "$api/state" | jq -c --arg m "$mode" '.runs[$m]')
  done_n=$(jq -r '.done' <<<"$r"); printf '\r   %s/%s' "$done_n" "$n"
  [[ "$(jq -r '.finished // empty' <<<"$r")" != "" ]] && break; sleep 2
done; echo
jq -r '.summary | "   warm KV-cache hits  \(.warm)/\(.ok)\n   average latency     \(.avg_ms) ms\n   p95 latency         \(.p95_ms) ms\n   prompt tokens cached \(.cached_tokens) of \(.prompt_tokens)"' <<<"$r"
jq -r '"   requests per GPU    " + ([.results[] | select(.gpu >= 0) | .gpu] | group_by(.) | map("\(["A","B","C"][.[0]])=\(length)") | join("  "))' <<<"$r"
