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

echo "==> Checking for Node/npm..."

# Try to source an existing system-wide nvm (if any)
export NVM_DIR="/usr/local/share/nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" || true

# If node is still missing, install our own nvm + Node 22
if ! command -v node >/dev/null 2>&1; then
  echo "    node not found; installing nvm + Node 22..."
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  # shellcheck source=/dev/null
  source "$NVM_DIR/nvm.sh"
  nvm install 22
  nvm use 22
fi

if command -v npm >/dev/null 2>&1; then
  echo "==> npm detected, updating to latest..."
  npm install -g npm@latest

  echo "==> Installing pnpm..."
  npm install -g pnpm
else
  echo "    npm still not found on PATH; skipping Node/pnpm bootstrap."
fi

echo "==> Installing MinIO client (mc)..."
mkdir -p "$HOME/.local/bin"
curl -sSL https://dl.min.io/client/mc/release/linux-amd64/mc -o "$HOME/.local/bin/mc"
chmod +x "$HOME/.local/bin/mc"

if command -v npm >/dev/null 2>&1; then
  echo "==> Installing concurrently..."
  npm install -g concurrently
else
  echo "    npm not found; skipping global concurrently install."
fi

echo "==> Installing Node dependencies..."
# Prefer current working directory (where devcontainer runs postCreate from),
# but fall back to common workspace paths if needed.
if [ -d "/workspaces/probate-app" ]; then
  cd /workspaces/probate-app
fi

if command -v pnpm >/dev/null 2>&1; then
  if [ -f package.json ]; then
    pnpm install
  else
    echo "    No package.json yet — skipping (will run once monorepo is scaffolded)"
  fi
else
  echo "    pnpm not found; skipping Node dependency install."
fi

echo "==> Syncing Python dependencies..."
# Python services will be synced once scaffolded; no-op until services/ exists
if [ -f /workspaces/probate-app/pyproject.toml ]; then
  cd /workspaces/probate-app
  uv sync --all-packages
fi

echo "==> Setting default working directory to /workspaces/probate-app..."
echo 'cd /workspaces/probate-app' >> ~/.bashrc
echo 'cd /workspaces/probate-app' >> ~/.zshrc

echo "==> postCreate complete."
