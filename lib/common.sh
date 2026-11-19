# shellcheck shell=bash
# Output and reporting shared by every phase.
#
# A terminal gets coloured lines. A CI run also gets a Markdown report: one table row per phase
# (result, time, the F5 guide page), every planned change, and the diffs against the live cluster.
# It goes to $GITHUB_STEP_SUMMARY (GitHub and Gitea both render it on the run page) and to
# $BNK_REPORT_MD when set, which is what the plan workflow posts on the pull request.

_SUMMARY="$(mktemp)"      # free-form notes and diffs
_PHASES="$(mktemp)"       # one table row per phase
_CHANGES="$(mktemp)"      # one line per change a plan found
export _SUMMARY _PHASES _CHANGES
_sum() { printf '%s\n' "$*" >> "$_SUMMARY"; }

banner() { printf '\n\033[1m  %s\033[0m\n' "$*"; BNK_BANNER="$*"; }
log()    { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
docref() { printf '    \033[2mF5 guide: %s\033[0m\n' "$*"; }
ok()     { printf '    \033[0;32mok\033[0m  %s\n' "$*"
           # a plan's "would ..." lines are its change list
           if [[ "$*" == plan:\ would* ]]; then printf '%s\n' "${*#plan: }" >> "$_CHANGES"; fi; }
warn()   { printf '    \033[0;33m!!\033[0m  %s\n' "$*"; _PHASE_WARN=1
           if [[ "${BNK_STRICT_PREFLIGHT:-false}" == "true" && "${_IN_PREFLIGHT:-0}" == "1" ]]; then
             printf '    \033[0;31mXX\033[0m  strict environment %s: preflight warnings are fatal\n' "${BNK_ENV_NAME:-}" >&2
             exit 1
           fi; }
# progress while waiting for something that is still starting (a retry is not a warning)
wait_note() { printf '    \033[2m..\033[0m  %s\n' "$*"; }
die()    { printf '    \033[0;31mXX\033[0m  %s\n' "$*" >&2; _PHASE_ERR="$*"; exit 1; }
# A diff against the live cluster, shown collapsed in the report.
report_diff() {  # report_diff <title> <diff text>
  [[ -n "$2" ]] || return 0
  printf '%s\n' "$1" >> "$_CHANGES"
  { echo; echo "<details><summary>${1}</summary>"; echo; echo '```diff'; printf '%s\n' "$2"; echo '```'; echo '</details>'; } >> "$_SUMMARY"
}
export -f _sum log ok warn wait_note die docref report_diff

phase_begin() { _P_ID="$1"; _P_TITLE="$2"; _P_DOC="$3"; _P_T0=$(date +%s); _PHASE_WARN=0; _PHASE_ERR=""; }
phase_end() {
  local d=$(( $(date +%s) - _P_T0 )) r="✅"
  [[ "${_PHASE_WARN:-0}" == 1 ]] && r="⚠️"
  printf '| `%s` | %s | %s | %ss | [guide](%s) |\n' "$_P_ID" "$_P_TITLE" "$r" "$d" "$_P_DOC" >> "$_PHASES"
  _P_ID=""
}

# Who installed this, from what: stamped on the CNEInstance and appended to a ledger ConfigMap, so
# the answer lives in the cluster (and in Forge's view of it), not in someone's memory.
record_provenance() {
  local by="${BNK_ORCHESTRATOR:-}" run="" commit="${GITHUB_SHA:-${BNK_HOST_COMMIT:-}}" now actor
  # GNU id prints the bare uid and fails when the uid has no name (the runner image's uid 1000).
  actor="${GITHUB_ACTOR:-}"
  if [[ -z "$actor" ]]; then
    actor="$(id -un 2>/dev/null || true)"
    [[ -z "$actor" || "$actor" =~ ^[0-9]+$ ]] && actor="${by:-runner}-runner"
  fi
  [[ -z "$by" && -n "${GITHUB_ACTIONS:-}" ]] && by=pipeline
  [[ -n "${GITHUB_RUN_ID:-}" ]] && run="${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID}"
  [[ -z "$commit" || "$commit" == unknown ]] && commit="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kubectl -n "$NS_BNK" annotate cneinstance f5-bnk-instance --overwrite \
    "bnk-host-deploy.io/commit=${commit}" "bnk-host-deploy.io/orchestrator=${by:-manual}" \
    "bnk-host-deploy.io/actor=${actor}" "bnk-host-deploy.io/applied-at=${now}" \
    "bnk-host-deploy.io/run=${run:-none}" "bnk-host-deploy.io/release=${BNK_VERSION}" >/dev/null 2>&1 || true
  local entry; entry="$(printf '{"at":"%s","by":"%s","actor":"%s","commit":"%s","release":"%s","run":"%s"}' \
    "$now" "${by:-manual}" "$actor" "$commit" "$BNK_VERSION" "$run")"
  kubectl -n "$NS_CORE" create configmap bnk-deploy-ledger --dry-run=client -o yaml 2>/dev/null \
    | kubectl apply -f - >/dev/null 2>&1 || true
  kubectl -n "$NS_CORE" patch configmap bnk-deploy-ledger --type merge \
    -p "{\"data\":{\"${now//:/-}\":$(jq -Rn --arg e "$entry" '$e')}}" >/dev/null 2>&1 || true
  ok "provenance: commit ${commit:0:12} by ${by:-manual} (${actor}), recorded on the CNEInstance and in ${NS_CORE}/bnk-deploy-ledger"
}

_emit_summary() {
  local rc=$? report
  # the phase that was running when we exited did not finish
  if [[ -n "${_P_ID:-}" ]]; then
    printf '| `%s` | %s | ❌ | %ss | [guide](%s) |\n' "$_P_ID" "$_P_TITLE" "$(( $(date +%s) - _P_T0 ))" "$_P_DOC" >> "$_PHASES"
  fi
  report="$(mktemp)"
  {
    echo "### ${BNK_BANNER:-bnk-host-deploy}"
    echo
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      if [[ -s "$_CHANGES" ]]; then
        echo "**$(grep -c . "$_CHANGES") planned change(s)**"; echo
        sed 's/^/- /' "$_CHANGES"
      else
        echo "**No changes.** The cluster already matches this commit."
      fi
      echo
    fi
    if [[ -s "$_PHASES" ]]; then
      echo "| Phase | Step | Result | Time | F5 guide |"
      echo "|---|---|---|---|---|"
      cat "$_PHASES"
    fi
    [[ -n "${_PHASE_ERR:-}" ]] && { echo; echo "**Failed:** ${_PHASE_ERR}"; }
    cat "$_SUMMARY"
    if [[ "${DRY_RUN:-0}" == "0" && "$rc" == 0 ]] && command -v kubectl >/dev/null 2>&1; then
      echo; echo '```'
      echo "licence      $(kubectl get license.k8s.f5net.com -n "${NS_CORE:-f5-cne-core}" -o jsonpath='{.items[0].status.state}' 2>/dev/null || echo none)"
      echo "CNEInstance  $(kubectl get cneinstance -n "${NS_BNK:-f5-bnk}" -o jsonpath='{.items[0].spec.manifestVersion} Available={.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo -)"
      echo "TMM          $(kubectl get ds -n "${NS_BNK:-f5-bnk}" f5-tmm -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled} ready' 2>/dev/null || echo 'not deployed')"
      echo '```'
    fi
  } > "$report"
  [[ -n "${BNK_REPORT_MD:-}" ]] && cp "$report" "$BNK_REPORT_MD"
  [[ -n "${BNK_CHANGES_FILE:-}" ]] && cp "$_CHANGES" "$BNK_CHANGES_FILE"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -w "$(dirname "${GITHUB_STEP_SUMMARY}")" ]]; then cat "$report" >> "$GITHUB_STEP_SUMMARY"; fi
  rm -f "$_SUMMARY" "$_PHASES" "$_CHANGES" "$report"
}
trap _emit_summary EXIT
