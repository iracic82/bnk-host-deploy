#!/usr/bin/env bash
# lab dynamo: the inference runtime the AI team's models run on: NVIDIA Dynamo 1.5.1 (operator) with
# NATS, Dynamo's event plane. Model workers publish their KV-cache events on NATS, and BNK's endpoint
# picker (F5EPP, engine dynamo) subscribes to them: that is how the picker knows which GPU holds which
# prompt. A platform component, like Argo CD: install it once, before the AI team ships models.
source "$(dirname "$0")/../lib.sh"
DYNAMO_VERSION=1.5.1
step "1/3  NVIDIA Dynamo platform ${DYNAMO_VERSION} (operator + NATS) in dynamo-system"
helm upgrade --install dynamo-platform "https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${DYNAMO_VERSION}.tgz" \
  -n dynamo-system --create-namespace --set global.nats.install=true --wait --timeout 15m >/dev/null \
  || fail "dynamo-platform did not install"
kubectl -n dynamo-system rollout status statefulset/dynamo-platform-nats --timeout=300s >/dev/null || fail "NATS is not ready"
ok "Dynamo operator and NATS running"

step "2/3  NATS only for endpoint-picker namespaces"
# NATS has no authentication. Anyone who can publish KV events could steer BNK's picker, so only the
# namespaces the platform approved for pickers (phase 47 labels them) and dynamo-system may connect.
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: nats-picker-namespaces-only, namespace: dynamo-system}
spec:
  podSelector: {matchLabels: {app.kubernetes.io/name: nats, app.kubernetes.io/instance: dynamo-platform}}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {bnk-host-deploy.io/epp: "true"}}
    - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: dynamo-system}}
    ports: [{protocol: TCP, port: 4222}]
YAML
ok "NetworkPolicy: NATS (4222) admits only namespaces labelled bnk-host-deploy.io/epp=true"

step "3/3  model namespace ready for Dynamo workers"
kubectl get ns inference >/dev/null 2>&1 || fail "namespace inference does not exist: land the platform change first (clusters/lab.yaml inference.epp_namespaces)"
# the workers read an optional Hugging Face token from this secret; the lab's model is public, so it is empty
kubectl -n inference create secret generic hf-token-secret --from-literal=HF_TOKEN= --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "inference: hf-token-secret present (empty, the model is public)"
