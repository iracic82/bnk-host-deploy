# shellcheck shell=bash
# Helpers for the Instruqt check and solve scripts: Gitea pull requests and Actions runs, and the
# state of BNK. Sourced after lib.sh.
REPO_PATH="/repos/${GITEA_ORG}/${GITEA_REPO}"

# The newest run of a workflow file (e.g. plan.yml), optionally for one commit. Prints JSON or nothing.
latest_run() {  # latest_run <workflow file> [head sha]
  gitea_api GET "${REPO_PATH}/actions/runs?limit=50" 2>/dev/null \
    | jq -c --arg w "$1" --arg s "${2:-}" '[(.workflow_runs // [])[]
        | select((.path // "" | test("(^|/)" + $w + "(@.*)?$")) and ($s == "" or .head_sha == $s))]
        | sort_by(.id) | last // empty'
}
run_state() {  # run_state <workflow> [sha] -> "status/conclusion", e.g. completed/success
  latest_run "$@" | jq -r 'if . == null then "none" else "\(.status)/\(.conclusion // "")" end' 2>/dev/null || echo none
}
wait_run() {  # wait_run <workflow> <sha> <seconds>: waits for completion, prints the conclusion
  local end=$(( $(date +%s) + $3 )) st=""
  while [[ $(date +%s) -lt $end ]]; do
    st=$(run_state "$1" "$2")
    case "$st" in completed/*) echo "${st#completed/}"; return 0 ;; esac
    sleep 15
  done
  echo "timeout($st)"; return 1
}
# run_debug <workflow> [sha]: after a run that did not succeed, print what Gitea and the runner know.
run_debug() {
  local run id
  run=$(latest_run "$@" 2>/dev/null); id=$(jq -r '.id // empty' <<<"$run")
  echo "---- $1 run ${id:-?}: $(jq -c '{status, conclusion, event, head_sha}' <<<"$run" 2>/dev/null)"
  if [[ -n "$id" ]]; then
    gitea_api GET "${REPO_PATH}/actions/runs/${id}/jobs" 2>/dev/null \
      | jq -r '(.jobs // [])[] | "job \(.id) \(.name): \(.status)/\(.conclusion // "") steps: \([(.steps // [])[] | "\(.name)=\(.conclusion // .status)"] | join(", "))"' 2>/dev/null || true
    for j in $(gitea_api GET "${REPO_PATH}/actions/runs/${id}/jobs" 2>/dev/null | jq -r '(.jobs // [])[].id' 2>/dev/null); do
      echo "---- job $j log (tail)"; gitea_api GET "${REPO_PATH}/actions/jobs/${j}/logs" 2>/dev/null | tail -40 || true
    done
  fi
  echo "---- runner journal (tail)"; journalctl -u gitea-runner --no-pager -n 40 2>/dev/null || true
}
pr_for_branch() {  # pr_for_branch <branch> [state]: PR number or nothing
  gitea_api GET "${REPO_PATH}/pulls?state=${2:-all}&limit=50" | jq -r --arg b "$1" '[.[] | select(.head.ref == $b)] | sort_by(.number) | last | .number // empty'
}
open_pr() {  # open_pr <branch> <title> [body]
  local n; n=$(pr_for_branch "$1" open)
  [[ -n "$n" ]] && { echo "$n"; return; }
  jq -n --arg h "$1" --arg t "$2" --arg b "${3:-}" '{head:$h, base:"main", title:$t, body:$b}' \
    | curl -fsS -X POST -u "${LAB_USER}:$(lab_secret gitea-password)" -H 'Content-Type: application/json' \
        --data @- "http://127.0.0.1:${PORT_GITEA}/api/v1${REPO_PATH}/pulls" | jq -r .number
}
# Gitea answers 405 while it is still computing a new PR's mergeability, or while required status
# checks (the ci workflow) are pending. Retry for up to 5 minutes, then show Gitea's own reason.
merge_pr() {  # merge_pr <number>
  local i code out; out=$(mktemp)
  for i in $(seq 1 60); do
    code=$(curl -sS -o "$out" -w '%{http_code}' -X POST -u "${LAB_USER}:$(lab_secret gitea-password)" \
      -H 'Content-Type: application/json' --data '{"Do":"merge"}' \
      "http://127.0.0.1:${PORT_GITEA}/api/v1${REPO_PATH}/pulls/$1/merge") || code=000
    [[ "$code" =~ ^2 ]] && { rm -f "$out"; return 0; }
    [[ "$code" == 405 || "$code" == 409 ]] || break
    (( i == 1 )) && echo "   waiting for pull request #$1 to become mergeable (checks running)..." >&2
    sleep 5
  done
  echo "Gitea refused to merge #$1 ($code): $(head -c 300 "$out")" >&2; rm -f "$out"; return 1
}
main_sha() { gitea_api GET "${REPO_PATH}/branches/main" | jq -r .commit.id; }
file_on_main() { curl -fsS "http://127.0.0.1:${PORT_GITEA}/${GITEA_ORG}/${GITEA_REPO}/raw/branch/main/$1"; }

bnk_available() {
  [[ "$(kubectl -n f5-bnk get cneinstance f5-bnk-instance -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)" == True ]]
}
wait_bnk() {  # wait_bnk <seconds>
  local end=$(( $(date +%s) + $1 ))
  while [[ $(date +%s) -lt $end ]]; do bnk_available && return 0; sleep 20; done
  return 1
}
