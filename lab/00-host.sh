#!/usr/bin/env bash
# Host prerequisites and tools. The only step that changes the kernel.
#   hugepages  TMM requests hugepages-2Mi; kind nodes share this kernel, so the pages are reserved here
#   inotify    three kind nodes plus ~80 BNK pods exhaust the defaults ("too many open files")
#   fs.aio     TMM uses async io; the default context count runs out on a busy node
source "$(dirname "$0")/lib.sh"
# shellcheck source=versions.env
source "$LAB_REPO_DIR/versions.env"

step "kernel settings"
cat > /etc/sysctl.d/90-bnk-lab.conf <<EOF
vm.nr_hugepages = ${NR_HUGEPAGES}
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 1048576
fs.aio-max-nr = 1048576
net.ipv4.ip_forward = 1
EOF
sysctl -q -p /etc/sysctl.d/90-bnk-lab.conf
hp=$(awk '/HugePages_Total/{print $2}' /proc/meminfo)
if [[ "$hp" -lt "$NR_HUGEPAGES" ]]; then sync; echo 3 > /proc/sys/vm/drop_caches; sysctl -q -w vm.nr_hugepages="$NR_HUGEPAGES"; fi
hp=$(awk '/HugePages_Total/{print $2}' /proc/meminfo)
[[ "$hp" -ge "$NR_HUGEPAGES" ]] || fail "asked for $NR_HUGEPAGES hugepages, got $hp"
ok "hugepages ${hp} x 2Mi, inotify and aio raised"

step "base tools (the image carries docker, kind, kubectl, helm)"
for t in docker kind containerlab kubectl helm git jq curl python3 make openssl; do need "$t"; done
docker info >/dev/null 2>&1 || fail "docker is not running"
export DEBIAN_FRONTEND=noninteractive
command -v shellcheck >/dev/null || { apt-get update -qq >/dev/null; apt-get install -y -qq shellcheck xz-utils >/dev/null; }
command -v xz >/dev/null || apt-get install -y -qq xz-utils >/dev/null

fetch() { curl -fsSL --retry 4 --retry-delay 3 -o "$2" "$1"; }
T=$(mktemp -d)

if ! yq --version 2>/dev/null | grep -q "${YQ_VERSION}"; then
  fetch "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" "$T/yq"
  fetch "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/checksums-bsd" "$T/yq.sums"
  (cd "$T" && sed -n 's/^SHA256 (yq_linux_amd64) = \(.*\)$/\1  yq/p' yq.sums | sha256sum -c - >/dev/null) || fail "yq checksum"
  install -m 0755 "$T/yq" /usr/local/bin/yq
fi
ok "yq $(yq --version | awk '{print $NF}')"

if ! node --version 2>/dev/null | grep -q "^${NODE_VERSION}$"; then
  f="node-${NODE_VERSION}-linux-x64.tar.xz"
  fetch "https://nodejs.org/dist/${NODE_VERSION}/${f}" "$T/$f"
  fetch "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" "$T/node.sums"
  (cd "$T" && grep " ${f}\$" node.sums | sha256sum -c - >/dev/null) || fail "node checksum"
  mkdir -p /opt/node && tar -xJf "$T/$f" -C /opt/node --strip-components=1
  ln -sf /opt/node/bin/node /usr/local/bin/node; ln -sf /opt/node/bin/npm /usr/local/bin/npm
fi
ok "node $(node --version) (runs actions/checkout in host-mode CI jobs)"
rm -rf "$T"

for t in kind kubectl helm; do ok "$t $(command -v $t)"; done
[[ "$(nproc)" -ge 24 ]] || warn "$(nproc) vCPU; BNK requests ~22.5"
