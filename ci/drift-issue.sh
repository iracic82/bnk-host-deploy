#!/usr/bin/env bash
# Keeps one open issue titled "Drift: ..." in sync with reality: opened (or updated) when the
# nightly plan finds differences, closed with a comment when a run finds none.
#   ci/drift-issue.sh <0|1> <markdown-file>
set -euo pipefail
drifted="$1"; file="$2"; title="Drift: a cluster no longer matches main"
: "${GITHUB_TOKEN:?}" "${GITHUB_API_URL:?}" "${GITHUB_REPOSITORY:?}"
api() { curl -fsS -H "Authorization: token ${GITHUB_TOKEN}" -H 'Content-Type: application/json' "$@"; }
R="${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}"
open=$(api "$R/issues?state=open&type=issues&limit=50&per_page=100" | jq -r --arg t "$title" '[.[] | select(.title == $t)] | first | .number // empty')
run="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
if [[ "$drifted" == 1 ]]; then
  body="$(printf 'The nightly plan found differences between the live cluster(s) and `main` (%s).\n\nEither revert the hand change (re-run **deploy**), or make it official in a pull request.\n\n%s' "$run" "$(tail -c 55000 "$file")")"
  if [[ -n "$open" ]]; then
    jq -n --arg b "$body" '{body:$b}' | api -X PATCH --data @- "$R/issues/$open" >/dev/null; echo "drift issue #$open updated"
  else
    jq -n --arg t "$title" --arg b "$body" '{title:$t, body:$b}' | api -X POST --data @- "$R/issues" | jq -r '"drift issue #\(.number) opened"'
  fi
elif [[ -n "$open" ]]; then
  jq -n --arg b "No drift in $run. Closing." '{body:$b}' | api -X POST --data @- "$R/issues/$open/comments" >/dev/null
  api -X PATCH --data '{"state":"closed"}' "$R/issues/$open" >/dev/null; echo "drift issue #$open closed"
else
  echo "no drift"
fi
