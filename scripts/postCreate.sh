#!/usr/bin/env bash
# Runs once when the devcontainer is first created.
set -euo pipefail

echo "==> Installing postgresql-client (for pg_isready)..."
sudo apt-get update -qq && sudo apt-get install -y -qq postgresql-client

echo "==> Installing uv (Python package manager)..."
curl -LsSf https://astral.sh/uv/install.sh | sh
# Source the env file uv installer creates so uv is immediately on PATH
# shellcheck source=/dev/null
source "$HOME/.local/bin/env" 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"

# The devcontainer Node feature installs via nvm; source it so npm is on PATH
export NVM_DIR="/usr/local/share/nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

echo "==> Updating npm to latest..."
npm install -g npm@latest

echo "==> Installing pnpm..."
npm install -g pnpm

echo "==> Installing MinIO client (mc)..."
mkdir -p "$HOME/.local/bin"
curl -sSL https://dl.min.io/client/mc/release/linux-amd64/mc -o "$HOME/.local/bin/mc"
chmod +x "$HOME/.local/bin/mc"

echo "==> Installing concurrently..."
npm install -g concurrently

echo "==> Installing Node dependencies..."
cd /workspace
if [ -f package.json ]; then
  pnpm install
else
  echo "    No package.json yet — skipping (will run once monorepo is scaffolded)"
fi

echo "==> Syncing Python dependencies..."
# Python services will be synced once scaffolded; no-op until services/ exists
if [ -f /workspace/pyproject.toml ]; then
  uv sync --all-packages
fi

echo "==> postCreate complete."
