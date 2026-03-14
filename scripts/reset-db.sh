#!/usr/bin/env bash
# Stop apps, drop all data, re-migrate, re-seed. Leaves the app ready to start.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
cd /workspace

echo "==> Stopping running services..."
bash "$(dirname "$0")/stop.sh" || true

echo "==> Dropping and recreating database..."
PGPASSWORD=probate psql -h postgres -U probate -d postgres \
  -c "DROP DATABASE IF EXISTS probate;" \
  -c "CREATE DATABASE probate;"

echo "==> Flushing Redis..."
redis-cli -h redis FLUSHALL

echo "==> Running migrations..."
cd /workspace/services/api
uv run alembic upgrade head
cd /workspace

echo "==> Seeding..."
uv run python -m scripts.seed

echo "==> Recreating MinIO buckets..."
mc alias set local http://minio:9000 minioadmin minioadmin --quiet 2>/dev/null || true
mc rb --force local/documents 2>/dev/null || true
mc rb --force local/petitions 2>/dev/null || true
mc mb local/documents local/petitions

echo "==> Done. Run: bash scripts/start.sh"
