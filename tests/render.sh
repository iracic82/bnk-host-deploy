#!/usr/bin/env bash
# Renders the CNEInstance exactly as phase 50 would and checks the result: every placeholder
# substituted, valid YAML, and the fields the CRD requires present with the pinned values.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
source versions.env; source environments/lab.env; source profiles/host.env; source lib/render.sh
_render_sc=standard
out="$(render_cneinstance profiles/host.yaml)"
grep -q '__[A-Z]*__' <<<"$out" && { echo "unsubstituted placeholder:"; grep '__[A-Z]*__' <<<"$out"; exit 1; }
yq -e '.' >/dev/null <<<"$out"
[[ "$(yq -r .spec.manifestVersion <<<"$out")" == "$CNE_RELEASE_MANIFEST" ]] || { echo "manifestVersion != $CNE_RELEASE_MANIFEST"; exit 1; }
for k in .spec.certificate.clusterIssuer .spec.deploymentSize .spec.product.type .spec.registry.uri; do
  [[ -n "$(yq -r "$k // \"\"" <<<"$out")" ]] || { echo "missing $k"; exit 1; }
done
[[ "$(yq -r .spec.dpu.enabled <<<"$out")" == "false" ]] || { echo "host profile must not enable the DPU"; exit 1; }
BNK_WATCH_NAMESPACES=a,b out2="$(render_cneinstance profiles/host.yaml)"
[[ "$(yq -r '.spec.watchNamespaces | length' <<<"$out2")" == "2" ]] || { echo "watchNamespaces not rendered"; exit 1; }
echo "render: ok (manifest $CNE_RELEASE_MANIFEST)"

# The lab cluster's shape: two TMM legs and the legacy network model.
export HERE=$PWD
# shellcheck source=lib/cluster.sh
source lib/cluster.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cp clusters/lab.yaml clusters/lab.attachments.yaml clusters/lab.network.yaml "$t/"
yq -i '.enabled = true | .tmm.nodes = ["bnk-worker"]' "$t/lab.yaml"
load_cluster "$t/lab.yaml"; BNK_TMM_MAPRES=true
out3="$(render_cneinstance profiles/host.yaml)"
yq -e '.' >/dev/null <<<"$out3"
[[ "$(yq -r '.spec.networkAttachments | join(",")' <<<"$out3")" == "external-net,internal-net" ]] || { echo "networkAttachments wrong"; exit 1; }
[[ "$(yq -r '.spec.advanced.cneController.env[0].value' <<<"$out3")" == "false" ]] || { echo "USE_GATEWAY_SETTINGS not rendered"; exit 1; }
yq -r '.spec.advanced.pseudoCNI.env[] | select(.name=="EXCLUDE_CIDR") | .value' <<<"$out3" | grep -q '10.30.30.0/24' || { echo "EXCLUDE_CIDR misses the VIP pool"; exit 1; }
yq -r '.spec.advanced.tmm.env[] | select(.name=="TMM_MAPRES_ADDL_VETHS_ON_DP") | .value' <<<"$out3" | grep -q true || { echo "MAPRES not on"; exit 1; }
echo "render: ok (lab shape: 2 legs, legacy network model, EXCLUDE_CIDR=$(yq -r '.spec.advanced.pseudoCNI.env[] | select(.name=="EXCLUDE_CIDR") | .value' <<<"$out3"))"
