#!/usr/bin/env bash
# Stop all development processes started by start.sh.
set -uo pipefail

echo "==> Stopping development services..."
pkill -f "uvicorn app.main"   2>/dev/null && echo "  stopped: FastAPI"   || echo "  not running: FastAPI"
pkill -f "celery -A tasks"    2>/dev/null && echo "  stopped: Celery"    || echo "  not running: Celery"
pkill -f "next dev"           2>/dev/null && echo "  stopped: Admin web" || echo "  not running: Admin web"
pkill -f "expo start"         2>/dev/null && echo "  stopped: Expo"      || echo "  not running: Expo"
pkill -f "concurrently"       2>/dev/null || true

echo "==> Done."
