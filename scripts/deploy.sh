#!/usr/bin/env bash
# Universal deploy wrapper — called by project-level deploy scripts
# Usage: deploy.sh <environment> [extra ansible-playbook args...]
#
# Expected directory layout (when called from project's ci-scripts/):
#   ci-scripts/
#     baseline/           ← this repo (submodule)
#     ansible/            ← project overlay
#       ansible.cfg
#       inventories/<env>/
set -euo pipefail

ENV="${1:?Usage: deploy.sh <environment> [ansible-playbook args...]}"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve project ansible dir (one level up from baseline, then into ansible/)
PROJECT_ANSIBLE_DIR="$(cd "$BASELINE_DIR/../ansible" && pwd)"

cd "$PROJECT_ANSIBLE_DIR"

INVENTORY="inventories/${ENV}/${ENV}.yml"
PLAYBOOK="../baseline/ansible/playbooks/deploy/deploy-all.yml"

if [ ! -f "$INVENTORY" ]; then
  echo "ERROR: Inventory not found: $PROJECT_ANSIBLE_DIR/$INVENTORY"
  exit 1
fi

ansible-playbook -i "$INVENTORY" "$PLAYBOOK" "$@"
