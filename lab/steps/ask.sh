#!/usr/bin/env bash
# lab ask [--rr] [customer] "question"   one chat request through BNK, as customer N (default 1)
#   --rr  through the round-robin VIP 10.30.30.12 instead of BNK's endpoint picker on 10.30.30.11
# The AI Inference tab sends the very same requests. Every one goes client -> router -> TMM -> a pod.
source "$(dirname "$0")/../lib.sh"
mode=picker; [[ "${1:-}" == "--rr" ]] && { mode=roundrobin; shift; }
cust=1; [[ "${1:-}" =~ ^[0-9]+$ ]] && { cust=$1; shift; }
q="${*:-How do I reach my service from outside the cluster?}"
jq -n --arg m "$mode" --argjson c "$cust" --arg q "$q" '{mode:$m, customer:$c, question:$q}' \
  | curl -s -m 60 -H 'Content-Type: application/json' --data-binary @- "http://127.0.0.1:${PORT_INFERENCE}/api/ask" \
  | jq -r 'if .ok then "\(.ms) ms  via \(.vip) (\(.mode))  customer \(.customer)  KV cache: \(.cached) of \(.prompt) prompt tokens \(if .cached > 0 then "(warm)" else "(cold, full prefill)" end)\n  \(.answer)" else "no answer: \(.error // .code)" end'
