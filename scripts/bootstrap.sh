#!/usr/bin/env bash
# Bootstrap script for ci-baseline
# Installs Ansible, Galaxy collections, and pre-commit hooks
set -euo pipefail

echo "=== Installing dependencies ==="

# Install Ansible
if ! command -v ansible &>/dev/null; then
  echo "Installing Ansible..."
  pip3 install --user ansible
fi

# Locate requirements.yml (works from both baseline and project overlay)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQ_FILE="$SCRIPT_DIR/../ansible/requirements.yml"

if [ ! -f "$REQ_FILE" ]; then
  echo "requirements.yml not found at $REQ_FILE"
  exit 1
fi

echo "Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r "$REQ_FILE"

# Install pre-commit
if ! command -v pre-commit &>/dev/null; then
  echo "Installing pre-commit..."
  pip3 install --user pre-commit
fi

# Setup pre-commit hooks if .pre-commit-config.yaml exists
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$REPO_ROOT/.pre-commit-config.yaml" ]; then
  echo "Setting up pre-commit hooks..."
  cd "$REPO_ROOT"
  pre-commit install
fi

echo "=== Done ==="
