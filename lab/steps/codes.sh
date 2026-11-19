#!/usr/bin/env bash
# lab codes [n] [url]: send n requests from the client (default 12, to the hello VIP) and print each
# HTTP status code on one line. 200 everywhere means no request failed.
n="${1:-12}"; url="${2:-http://10.30.30.10/}"
for _ in $(seq 1 "$n"); do docker exec client curl -s -m 5 -o /dev/null -w '%{http_code} ' "$url"; done
echo
