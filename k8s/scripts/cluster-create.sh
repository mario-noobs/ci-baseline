#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${1:-face-dev}
REGISTRY_NAME=k3d-registry.localhost
REGISTRY_PORT=5000

# ── Pre-flight checks ───────────────────────────────────────────────
if ! command -v k3d &>/dev/null; then
  echo "ERROR: k3d is not installed. Install it from https://k3d.io" >&2
  exit 1
fi

if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed. Install it from https://kubernetes.io/docs/tasks/tools/" >&2
  exit 1
fi

# ── Check if cluster already exists ────────────────────────────────
if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
  echo "Switching kubectl context..."
  k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context 2>/dev/null || true
  kubectl config use-context "k3d-${CLUSTER_NAME}"
  echo "Done. Use 'k3d cluster delete ${CLUSTER_NAME}' to recreate."
  exit 0
fi

# ── Registry ─────────────────────────────────────────────────────────
if k3d registry list 2>/dev/null | grep -q "registry.localhost"; then
  echo "Registry already exists, skipping creation."
else
  echo "Creating k3d registry..."
  k3d registry create registry.localhost --port "$REGISTRY_PORT"
fi

# ── Cluster ──────────────────────────────────────────────────────────
echo "Creating k3d cluster '${CLUSTER_NAME}'..."
k3d cluster create "$CLUSTER_NAME" \
  --api-port 6550 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --registry-use "$REGISTRY_NAME:$REGISTRY_PORT" \
  --agents 2 \
  --k3s-arg "--disable=traefik@server:0" \
  --wait

# ── Switch kubectl context ─────────────────────────────────────────
echo "Switching kubectl context to k3d-${CLUSTER_NAME}..."
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-merge-default --kubeconfig-switch-context 2>/dev/null || true
kubectl config use-context "k3d-${CLUSTER_NAME}"

echo "Waiting for nodes to be ready..."
for i in $(seq 1 30); do
  if kubectl get nodes &>/dev/null; then
    break
  fi
  echo "  Waiting for API server... ($i/30)"
  sleep 2
done
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# ── Nginx Ingress Controller ────────────────────────────────────────
echo "Installing nginx-ingress controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

echo "Waiting for nginx-ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# ── Namespaces ───────────────────────────────────────────────────────
echo "Creating namespaces..."
kubectl create namespace face-app --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace face-infra --dry-run=client -o yaml | kubectl apply -f -

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo "  Cluster '${CLUSTER_NAME}' is ready!"
echo "============================================="
echo "  Context  : k3d-${CLUSTER_NAME}"
echo "  Registry : ${REGISTRY_NAME}:${REGISTRY_PORT}"
echo "  API Port : 6550"
echo "  HTTP     : localhost:80"
echo "  HTTPS    : localhost:443"
echo "  Agents   : 2"
echo "  Namespaces: face-app, face-infra"
echo ""
echo "  kubectl cluster-info"
echo "============================================="
