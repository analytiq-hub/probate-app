#!/usr/bin/env bash
# Runs every time the devcontainer starts.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
export NVM_DIR="/usr/local/share/nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

echo "==> Starting sidecar services (postgres, redis, minio)..."
docker compose -f /workspace/.devcontainer/docker-compose.yml up -d

echo "==> Waiting for Postgres..."
until pg_isready -h localhost -U probate -q; do sleep 1; done

echo "==> Writing .env..."
cat > /workspace/.env <<'EOF'
# Database
DATABASE_URL=postgresql+asyncpg://probate:probate@localhost:5432/probate
DATABASE_URL_SYNC=postgresql+psycopg2://probate:probate@localhost:5432/probate
# Redis / Celery
REDIS_URL=redis://localhost:6379/0
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/1
# Storage
S3_ENDPOINT_URL=http://localhost:9000
S3_REGION=us-east-1
S3_BUCKET_DOCUMENTS=documents
S3_BUCKET_PETITIONS=petitions
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
# Auth
JWT_SECRET_KEY=dev-secret-change-in-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
# App
LOG_LEVEL=debug
ENVIRONMENT=development
EOF

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
mc alias set local http://localhost:9000 minioadmin minioadmin --quiet 2>/dev/null || true
mc mb --ignore-existing local/documents local/petitions 2>/dev/null || true

echo "==> postStart complete. Run: bash scripts/start.sh"
