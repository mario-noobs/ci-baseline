#!/usr/bin/env bash
set -euo pipefail

REGISTRY=k3d-registry.localhost:5000
PROJECT_ROOT=$(cd "${1:-.}" && pwd)
SERVICE_FILTER=${2:-}

# ── Service definitions ──────────────────────────────────────────────
# Format: image-name:build-context
declare -A SERVICES=(
  ["backend-service"]="$PROJECT_ROOT/backend-service"
  ["face-recognition-service"]="$PROJECT_ROOT/face-ai-service"
  ["gui-app"]="$PROJECT_ROOT/gui-app"
)

build_and_push() {
  local service=$1
  local context=$2

  echo "--------------------------------------------"
  echo "Building ${service}..."
  echo "  Context: ${context}"
  echo "  Image:   ${REGISTRY}/${service}:latest"
  echo "--------------------------------------------"

  docker build -t "${REGISTRY}/${service}:latest" "${context}"
  docker push "${REGISTRY}/${service}:latest"

  echo "${service} pushed successfully."
  echo ""
}

# ── Build ────────────────────────────────────────────────────────────
if [ -n "$SERVICE_FILTER" ]; then
  if [[ -v "SERVICES[$SERVICE_FILTER]" ]]; then
    build_and_push "$SERVICE_FILTER" "${SERVICES[$SERVICE_FILTER]}"
  else
    echo "ERROR: Unknown service '${SERVICE_FILTER}'." >&2
    echo "Available services: ${!SERVICES[*]}" >&2
    exit 1
  fi
else
  for service in "${!SERVICES[@]}"; do
    build_and_push "$service" "${SERVICES[$service]}"
  done
fi

echo "============================================="
echo "  All requested images built and pushed!"
echo "  Registry: ${REGISTRY}"
echo "============================================="
