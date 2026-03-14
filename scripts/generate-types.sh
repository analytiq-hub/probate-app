#!/usr/bin/env bash
# Regenerate TypeScript types from the FastAPI OpenAPI spec.
# Requires the API to be running (bash scripts/start.sh).
set -euo pipefail

cd /workspace

API_URL="${API_URL:-http://localhost:8000}"
OPENAPI_OUT="docs/openapi.json"
TYPES_OUT="packages/shared-types/src/api.ts"

echo "==> Fetching OpenAPI spec from $API_URL..."
curl -sf "$API_URL/openapi.json" -o "$OPENAPI_OUT"
echo "    Saved to $OPENAPI_OUT"

echo "==> Generating TypeScript types..."
mkdir -p "$(dirname "$TYPES_OUT")"
pnpm dlx openapi-typescript "$OPENAPI_OUT" -o "$TYPES_OUT"
echo "    Generated $TYPES_OUT"

echo "==> Done. Commit both $OPENAPI_OUT and $TYPES_OUT."
