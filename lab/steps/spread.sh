#!/usr/bin/env bash
# lab spread [n] [url]: send n requests from the client behind the edge router (default 12, to the hello
# VIP) and count which pod answered each. The answer's "Hostname:" line is the pod's name.
n="${1:-12}"; url="${2:-http://10.30.30.10/}"
for _ in $(seq 1 "$n"); do docker exec client curl -s -m 5 "$url" | grep Hostname; done | sort | uniq -c
