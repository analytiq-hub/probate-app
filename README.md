## Probate Document Automation Platform

This repository contains a full-stack platform for automating probate petition preparation:

- **Applicant mobile app**: React Native (Expo) for document capture and status tracking.
- **Admin web UI**: Next.js for reviewing cases, resolving conflicts, and generating petitions.
- **Backend API & worker**: FastAPI + Celery + PostgreSQL + Redis + S3-compatible storage for workflows, screening, extraction, and petition generation.

The high-level goal is to let applicants upload required documents from their phone while admins and lawyers review extracted data and download a finalized `.docx` petition.

---

## Stack & Architecture

- **Mobile**: React Native (Expo)
- **Web admin**: Next.js 15 (App Router), TypeScript
- **Backend API**: FastAPI (Python, async)
- **Worker**: Celery + Redis
- **Database**: PostgreSQL (SQLAlchemy async, Alembic)
- **Storage**: S3-compatible (e.g. MinIO) via `boto3`
- **Auth**:
  - FastAPI JWT (python-jose)
  - Mobile stores JWT in `expo-secure-store`
  - Admin web uses NextAuth.js calling `/auth/token`
- **Types**: FastAPI OpenAPI → `docs/openapi.json` → `openapi-typescript` → `packages/shared-types`
- **Dev environment**: DevPod + Docker Compose (Postgres, Redis, MinIO sidecars)

For more detail, see `docs/architecture.md` and `docs/implementation-plan.md`.

---

## Repository Structure

```text
probate-app/
  apps/
    applicant-mobile/     # React Native (Expo), iOS + Android
    admin-web/            # Next.js admin UI, desktop browser
  services/
    api/                  # FastAPI app (DB, auth, routes, storage)
      app/
        routers/          # Route modules (cases, documents, auth, admin, webhooks)
        models/           # SQLAlchemy ORM models
        schemas/          # Pydantic request/response schemas
        services/         # Business logic (case workflow, screening, extraction)
        core/             # Config, db session, auth, storage, logging
      alembic/            # Migrations
      pyproject.toml
    worker/               # Celery worker
      tasks/              # Task modules (screening, extraction, petition)
      pyproject.toml
  packages/
    shared-types/         # TS types generated from OpenAPI (do not edit manually)
  docs/
    architecture.md
    implementation-plan.md
    openapi.json          # Generated FastAPI OpenAPI spec
  .devcontainer/
    devcontainer.json
    docker-compose.yml
  scripts/
    devpod-setup.sh       # Provision DevPod workspace (host)
    start.sh              # Start API, worker, Expo, admin web (inside DevPod)
    stop.sh               # Stop dev processes
    reset-db.sh           # Drop + recreate DB, reseed
    generate-types.sh     # Regenerate TS types from FastAPI OpenAPI
```

---

## Local Development

All development is intended to run **inside a DevPod devcontainer** with Postgres, Redis, and MinIO managed by Docker Compose.

### 1. One-time DevPod setup (host)

From the repo root on your host machine:

```bash
bash scripts/devpod-setup.sh
```

This brings up the DevPod environment defined in `.devcontainer/devcontainer.json` and `.devcontainer/docker-compose.yml`.

### 2. First container start

On first start, the devcontainer will:

- Enable `corepack` and install JS deps via `pnpm install`.
- Install Python deps via `uv sync` for all workspace packages.
- Run Alembic migrations and seed initial data.

### 3. Running the full stack (inside DevPod)

Inside the DevPod terminal, from the repo root:

```bash
bash scripts/start.sh
```

This will:

- Create MinIO buckets for documents and petitions (if missing).
- Start:
  - FastAPI API on `http://localhost:8000`
  - Celery worker
  - Expo Metro bundler for the applicant app
  - Next.js admin web app

To stop everything:

```bash
bash scripts/stop.sh
```

To reset the database and reseed:

```bash
bash scripts/reset-db.sh
```

---

## Environment Variables

Core environment variables expected by the stack (see `docs/implementation-plan.md` for the full list and details):

```bash
# Database / Queue / Auth
DATABASE_URL
REDIS_URL
JWT_SECRET_KEY
JWT_ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES

# S3-Compatible Storage
S3_ENDPOINT_URL
S3_REGION
S3_BUCKET_DOCUMENTS
S3_BUCKET_PETITIONS
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY

# DocRouter Integration
DOCROUTER_API_URL
DOCROUTER_API_KEY
DOCROUTER_WEBHOOK_SECRET

# Mobile (Expo)
EXPO_PUBLIC_API_URL

# Admin Web
NEXT_PUBLIC_API_URL
NEXTAUTH_SECRET
NEXTAUTH_URL

# EAS / Misc
EXPO_TOKEN
LOG_LEVEL
```

DevPod sets reasonable defaults for local development via `.devcontainer/docker-compose.yml`. Production deployments should provide their own values via secrets/infra tooling.

---

## Apps & Services

- **Applicant mobile (`apps/applicant-mobile`)**
  - Expo Router screens for auth and case flows.
  - Native camera for document scanning (`expo-camera`, `expo-image-manipulator`).
  - React Query for API access; JWT stored in `expo-secure-store`.

- **Admin web (`apps/admin-web`)**
  - Next.js App Router with NextAuth.
  - Case queue, case detail, document viewer, extraction form, conflict warnings.
  - Uses shared TypeScript types from `packages/shared-types`.

- **API (`services/api`)**
  - FastAPI app exposing applicant, admin, and webhook routes.
  - SQLAlchemy async models + Alembic migrations.
  - JWT auth, RBAC, S3 storage helpers, DocRouter client, case state machine.

- **Worker (`services/worker`)**
  - Celery tasks for document screening, extraction polling, petition generation.
  - Integrates with DocRouter and S3; updates case state in the DB.

---

## Type Generation Workflow

TypeScript types for both frontends are generated from the FastAPI OpenAPI spec:

```bash
# Inside DevPod, with API running
bash scripts/generate-types.sh
```

This will:

- Download the latest OpenAPI schema to `docs/openapi.json` from the running API.
- Regenerate `packages/shared-types/src/api.ts` using `openapi-typescript`.

Commit the generated file so frontends can consume it without needing a running API.

---

## Project Phases

The implementation is organized into phases:

1. **Phase 0 — Foundation**: FastAPI scaffold, DB schema, auth, storage, DevPod.
2. **Phase 1 — Applicant Mobile**: Expo app, camera-based upload, checklist.
3. **Phase 2 — Jurisdiction Profiles**: YAML-driven jurisdiction data and requirements.
4. **Phase 3 — DocRouter & Worker**: Async screening, extraction, and state machine.
5. **Phase 4 — Admin Web UI**: Case queues, review UX, petition triggers.
6. **Phase 5 — Petition Generation**: `docxtpl` engine and `.docx` output.
7. **Phase 6 — Hardening**: Notifications, security, E2E tests, Docker deployment.

For detailed tasks and acceptance criteria per phase, read `docs/implementation-plan.md`.

---

## Contributing / Notes

- Do **not** edit generated TypeScript types in `packages/shared-types` by hand; use `scripts/generate-types.sh`.
- When adding new API routes or changing schemas, regenerate OpenAPI and types, and keep `docs/openapi.json` in sync.
- Prefer small, focused PRs aligned to a single phase or sub-task from the implementation plan.

