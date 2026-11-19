#!/usr/bin/env bash
# Posts a Markdown file as THE plan comment on a pull request: the first run creates it, every later
# run edits it in place, so the conversation shows one current plan, not a pile of stale ones.
# Issue-comment endpoints have the same shape on GitHub and Gitea, and both set GITHUB_API_URL.
#   ci/comment.sh <pr-number> <markdown-file> [marker]
set -euo pipefail
pr="${1:?pr number}"; file="${2:?markdown file}"; marker="<!-- ${3:-bnk-host-deploy:plan} -->"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}" "${GITHUB_API_URL:?}" "${GITHUB_REPOSITORY:?}"
api() { curl -fsS -H "Authorization: token ${GITHUB_TOKEN}" -H 'Content-Type: application/json' "$@"; }
body="$(printf '%s\n%s' "$marker" "$(tail -c 60000 "$file")")"
existing=$(api "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${pr}/comments?limit=50&per_page=100" 2>/dev/null \
  | jq -r --arg m "$marker" '[.[] | select(.body | startswith($m))] | last | .id // empty' || true)
if [[ -n "$existing" ]]; then
  jq -n --arg b "$body" '{body:$b}' | api -X PATCH --data @- "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/comments/${existing}" >/dev/null \
    && echo "plan comment updated on #${pr}" || echo "could not update the comment; the plan is in the job log"
else
  jq -n --arg b "$body" '{body:$b}' | api -X POST --data @- "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${pr}/comments" >/dev/null \
    && echo "plan posted on #${pr}" || echo "could not post the comment; the plan is in the job log"
fi
