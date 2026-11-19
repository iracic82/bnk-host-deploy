#!/usr/bin/env bash
# Puts the pinned yq and shellcheck on PATH for a CI job, if the runner lacks them. Versions come
# from versions.env so a hosted runner, a self-hosted runner and a laptop all check the same way.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
source versions.env
bin="${RUNNER_TEMP:-/tmp}/bnk-tools"; mkdir -p "$bin"
if ! command -v yq >/dev/null; then
  curl -fsSL -o "$bin/yq" "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
  curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/checksums-bsd" \
    | sed -n "s/^SHA256 (yq_linux_amd64) = \(.*\)$/\1  ${bin//\//\\/}\/yq/p" | sha256sum -c - >/dev/null
  chmod +x "$bin/yq"
fi
if ! command -v shellcheck >/dev/null; then
  curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
    | tar -xJ -C "$bin" --strip-components=1 "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
fi
# GitHub and Gitea both read GITHUB_PATH; outside CI just print the directory.
if [[ -n "${GITHUB_PATH:-}" ]]; then echo "$bin" >> "$GITHUB_PATH"; else echo "$bin"; fi
