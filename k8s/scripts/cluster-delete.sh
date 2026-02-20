#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${1:-face-dev}
DELETE_REGISTRY=false

# Parse flags
for arg in "$@"; do
  case $arg in
    --registry)
      DELETE_REGISTRY=true
      shift
      ;;
  esac
done

# ── Delete cluster ───────────────────────────────────────────────────
echo "Deleting k3d cluster '${CLUSTER_NAME}'..."
k3d cluster delete "$CLUSTER_NAME"
echo "Cluster '${CLUSTER_NAME}' deleted."

# ── Optionally delete registry ───────────────────────────────────────
if [ "$DELETE_REGISTRY" = true ]; then
  echo "Deleting k3d registry 'registry.localhost'..."
  k3d registry delete registry.localhost
  echo "Registry deleted."
else
  echo "Registry kept. Use --registry flag to delete it as well."
fi
