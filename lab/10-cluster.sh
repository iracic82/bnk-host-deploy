#!/usr/bin/env bash
# The Kubernetes cluster the learner installs BNK on: three kind nodes, Calico, hugepages, and the
# two extra NICs on bnk-worker that TMM's data-plane legs will use. No BNK, no cert-manager, no
# Multus: installing those is what the lab is about.
#
# The API server listens on the VM's address (not 127.0.0.1) so that containers outside the kind
# network, Forge's runner containers among them, can reach it with the same kubeconfig.
source "$(dirname "$0")/lib.sh"
# shellcheck source=versions.env
source "$LAB_REPO_DIR/versions.env"
IP=$(vm_ip); [[ -n "$IP" ]] || fail "cannot find the VM address"
KCFG=/root/.kube/config; mkdir -p /root/.kube

step "kind cluster '$KIND_CLUSTER' (API on $IP:6443)"
if ! kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
  cat > /root/.lab/kind.yaml <<KIND
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true          # Calico instead: the CNI F5 qualifies BNK with
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.96.0.0/12
  apiServerAddress: "${IP}"
  apiServerPort: 6443
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
nodes:
- role: control-plane
- role: worker
- role: worker
KIND
  kind create cluster --name "$KIND_CLUSTER" --image "$KIND_NODE_IMAGE" --config /root/.lab/kind.yaml \
    --kubeconfig "$KCFG" --wait 0s
fi
kind export kubeconfig --name "$KIND_CLUSTER" --kubeconfig "$KCFG" >/dev/null
kubectl config use-context "kind-$KIND_CLUSTER" >/dev/null
ok "nodes: $(kubectl get nodes --no-headers | awk '{print $1}' | paste -sd' ' -)"

step "containerd reads through the mirrors"
declare -A MIRRORS=( [docker.io]=5001 [quay.io]=5002 [ghcr.io]=5003 [registry.k8s.io]=5004 [repo.f5.com]=5006 [gcr.io]=5007 )
for n in $(kind get nodes --name "$KIND_CLUSTER"); do
  for up in "${!MIRRORS[@]}"; do
    docker exec "$n" sh -c "mkdir -p /etc/containerd/certs.d/$up && printf 'server = \"https://%s\"\n\n[host.\"http://172.18.0.1:%s\"]\n  capabilities = [\"pull\", \"resolve\"]\n' '$up' '${MIRRORS[$up]}' > /etc/containerd/certs.d/$up/hosts.toml"
  done
  # the lab's own registry (the runner image), plain HTTP on the kind gateway
  docker exec "$n" sh -c "mkdir -p /etc/containerd/certs.d/172.18.0.1:${PORT_REGISTRY} && printf '[host.\"http://172.18.0.1:${PORT_REGISTRY}\"]\n  capabilities = [\"pull\", \"resolve\"]\n' > /etc/containerd/certs.d/172.18.0.1:${PORT_REGISTRY}/hosts.toml"
done
ok "every node pulls via 172.18.0.1 (mirrors) and knows the lab registry 172.18.0.1:${PORT_REGISTRY}"

step "Calico ${CALICO_VERSION}"
kubectl get ns tigera-operator >/dev/null 2>&1 || \
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" >/dev/null
kubectl -n tigera-operator rollout status deploy/tigera-operator --timeout=300s >/dev/null
until kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; do sleep 2; done
kubectl apply -f - >/dev/null <<'EOC'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata: {name: default}
spec:
  calicoNetwork:
    ipPools:
    - {cidr: 192.168.0.0/16, encapsulation: VXLANCrossSubnet, natOutgoing: Enabled, nodeSelector: all()}
    nodeAddressAutodetectionV4: {interface: eth0}   # the kind network; eth1/eth2 belong to TMM
EOC
kubectl wait --for=condition=Ready node --all --timeout=600s >/dev/null
ok "nodes Ready with Calico"

step "hugepages visible to the kubelets"
# BNK's control plane needs every node's CPU, so the control plane runs workloads too.
kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1 || true
for n in $(kind get nodes --name "$KIND_CLUSTER"); do docker exec "$n" systemctl restart kubelet; done
for n in $(kind get nodes --name "$KIND_CLUSTER"); do
  for _ in $(seq 1 60); do
    hp=$(kubectl get node "$n" -o jsonpath='{.status.allocatable.hugepages-2Mi}' 2>/dev/null)
    [[ -n "$hp" && "$hp" != 0 ]] && break; sleep 3
  done
  ok "$n hugepages-2Mi=${hp:-0}"
done

step "CNI plugins on every node (kind ships four; TMM's legs need macvlan)"
CNI_PLUGINS=v1.9.1; T=$(mktemp -d)
curl -fsSL -o "$T/cni.tgz" "https://github.com/containernetworking/plugins/releases/download/$CNI_PLUGINS/cni-plugins-linux-amd64-$CNI_PLUGINS.tgz"
curl -fsSL -o "$T/cni.sha" "https://github.com/containernetworking/plugins/releases/download/$CNI_PLUGINS/cni-plugins-linux-amd64-$CNI_PLUGINS.tgz.sha256"
(cd "$T" && sed 's/  .*/  cni.tgz/' cni.sha | sha256sum -c - >/dev/null) || fail "CNI plugins checksum"
mkdir -p "$T/bin" && tar -xzf "$T/cni.tgz" -C "$T/bin"
for n in $(kind get nodes --name "$KIND_CLUSTER"); do
  for b in "$T"/bin/*; do docker exec "$n" test -x "/opt/cni/bin/$(basename "$b")" || docker cp "$b" "$n:/opt/cni/bin/"; done
done
rm -rf "$T"; ok "macvlan present on every node"

step "bnk-worker's data-plane NICs (the physical ports TMM will own)"
# eth1: into dc-edge, the data-center network the edge router sits on. The node itself keeps no
# address there; only TMM, through its macvlan, will.
docker network inspect dc-edge >/dev/null 2>&1 || docker network create dc-edge --subnet 10.10.10.0/24 --gateway 10.10.10.1 --ip-range 10.10.10.128/25 >/dev/null
docker network inspect dc-edge -f '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}' | grep -qw bnk-worker \
  || docker network connect dc-edge bnk-worker
w_eth1=$(docker exec bnk-worker sh -c "ip -o -4 addr | awk '/10\.10\.10\./{print \$2}'" | head -1)
[[ -n "$w_eth1" && "$w_eth1" != eth1 ]] && docker exec bnk-worker ip link set "$w_eth1" name eth1 2>/dev/null || true
docker exec bnk-worker ip -4 addr flush dev eth1
# eth2: a second leg into the kind network. A macvlan child cannot reach its own parent, so with
# eth0 as parent TMM could never talk to bnk-worker itself; eth2 is a parent that is not the node's.
BR="br-$(docker network inspect kind -f '{{.Id}}' | cut -c1-12)"
if ! docker exec bnk-worker ip link show eth2 >/dev/null 2>&1; then
  PID=$(docker inspect -f '{{.State.Pid}}' bnk-worker)
  ip link del tmm-int0 2>/dev/null || true
  ip link add tmm-int0 mtu 1500 type veth peer name eth2 mtu 1500 netns "$PID"
  ip link set tmm-int0 master "$BR" up
  docker exec bnk-worker ip link set eth2 up
fi
ok "bnk-worker: eth1 -> dc-edge (no node address), eth2 -> kind bridge $BR"

step "kubeconfigs"
# One for the VM (the learner, the CI runner) and one written for Forge, identical but standalone.
kubectl config view --minify --flatten > /root/.lab/kubeconfig-forge.yaml; chmod 600 /root/.lab/kubeconfig-forge.yaml
ok "API server $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
