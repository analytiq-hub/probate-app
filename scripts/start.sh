#!/usr/bin/env bash
# Start all development services inside the devpod.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

echo "==> Ensuring MinIO buckets exist..."
mc alias set local http://minio:9000 minioadmin minioadmin --quiet 2>/dev/null || true
mc mb --ignore-existing local/documents local/petitions 2>/dev/null || true

echo "==> Starting all services..."
# Use --tunnel so Expo Metro is reachable from a physical device or simulator
# outside the devcontainer. Switch to --localhost if running locally without
# devcontainer networking constraints.
concurrently \
  --names "api,worker,admin,expo" \
  --prefix-colors "cyan,yellow,green,magenta" \
  "cd services/api   && uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000" \
  "cd services/worker && uv run celery -A tasks worker --loglevel=info -B" \
  "cd apps/admin-web  && pnpm dev --port 3002" \
  "cd apps/applicant-mobile && npx expo start --tunnel"
