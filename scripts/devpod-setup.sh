#!/usr/bin/env bash
# Provision the DevPod workspace. Run once from the host machine.
# Requires: devpod CLI installed (https://devpod.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDE="${DEVPOD_IDE:-vscode}"  # override: DEVPOD_IDE=none bash scripts/devpod-setup.sh

echo "==> Provisioning DevPod workspace from $REPO_ROOT..."
echo "    IDE: $IDE"

devpod up "$REPO_ROOT" --ide "$IDE"

echo ""
echo "==> Workspace ready."
echo "    Once inside the devpod, run:  bash scripts/start.sh"
