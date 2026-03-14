#!/usr/bin/env bash
# Runs every time the devcontainer starts.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

echo "==> Waiting for Postgres..."
until pg_isready -h postgres -U probate -q; do sleep 1; done

echo "==> Running database migrations..."
if [ -f /workspace/services/api/alembic.ini ]; then
  cd /workspace/services/api
  uv run alembic upgrade head
  cd /workspace
fi

echo "==> Seeding database..."
if [ -f /workspace/scripts/seed.py ]; then
  cd /workspace
  uv run python -m scripts.seed
fi

echo "==> Creating MinIO buckets..."
mc alias set local http://minio:9000 minioadmin minioadmin --quiet 2>/dev/null || true
mc mb --ignore-existing local/documents local/petitions 2>/dev/null || true

echo "==> postStart complete. Run: bash scripts/start.sh"
