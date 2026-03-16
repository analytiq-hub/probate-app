# Probate Document Automation Platform — Implementation Plan

## Context

Building a probate petition automation platform. The applicant-facing app is **React Native (Expo)**. The admin UI is **Next.js**. The backend is **FastAPI**. The architecture spec lives in [docs/architecture.md](architecture.md).

**Key decisions made:**
- Applicant mobile app: **React Native (Expo)** — native camera, reliable push notifications, App Store + Play Store distribution
- Admin UI: **Next.js 15** (desktop-first, browser)
- Frontend monorepo: Turborepo + pnpm workspaces
- Backend API: **FastAPI** (Python)
- Backend worker: **Celery** + Redis
- ORM: **SQLAlchemy async** + **Alembic** migrations + PostgreSQL
- Petition generation: **`docxtpl`** (Python, Jinja-style `.docx` templates)
- Storage: S3-compatible (`boto3`)
- Auth: **FastAPI JWT** (python-jose); mobile app stores JWT in `expo-secure-store`; admin web uses NextAuth.js calling `/auth/token`
- Shared types: FastAPI auto-generates **OpenAPI spec**; `openapi-typescript` generates TS types for both frontend apps
- Dev environment: DevPod workspace running Docker Compose (postgres, redis, minio run as sidecars inside the DevPod)
- MVP focus: Applicant mobile app first

---

## Repository Structure

```
probate-app/
  apps/
    applicant-mobile/     # React Native (Expo), iOS + Android
    admin-web/            # Next.js admin UI, desktop browser
  services/
    api/                  # FastAPI app
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
  packages/               # Frontend-only shared packages
    shared-types/         # Auto-generated from OpenAPI spec (do not edit manually)
  docs/
    architecture.md
    implementation-plan.md
    openapi.json          # Generated FastAPI OpenAPI spec (committed, used for type-gen)
  scripts/
    devpod-setup.sh
    start.sh
    stop.sh
    reset-db.sh
    generate-types.sh     # Runs openapi-typescript against docs/openapi.json
```

**API boundary:** Both `applicant-mobile` and `admin-web` call the FastAPI app at `API_URL`. TypeScript types are generated from the FastAPI OpenAPI spec — never written by hand.

---

## DevPod & Local Development Environment

All development happens inside a **DevPod** workspace. The DevPod image includes Node.js, Python (via `uv`), and Docker; we run `docker compose` **inside** the DevPod using `docker-compose.dev.yml` in this repo. Sidecar services (postgres, redis, minio) start automatically via that compose file inside the DevPod — there is no nested devcontainer.

### Scripts (run inside the DevPod)

**`scripts/devpod-setup.sh`** — provision the workspace (run once on host)
```bash
#!/usr/bin/env bash
devpod up . --ide vscode   # or --ide none for headless
```

**`scripts/start.sh`** — start all services in development mode
```bash
#!/usr/bin/env bash
# Create MinIO buckets if missing
mc alias set local http://localhost:9000 minioadmin minioadmin 2>/dev/null || true
mc mb --ignore-existing local/documents local/petitions 2>/dev/null || true
# Start API, worker, Expo Metro bundler, and admin web concurrently
concurrently \
  "cd services/api && uv run uvicorn app.main:app --reload --port 8000" \
  "cd services/worker && uv run celery -A tasks worker --loglevel=info" \
  "cd apps/applicant-mobile && npx expo start --tunnel" \
  "cd apps/admin-web && pnpm dev"
```

> `--tunnel` exposes the Metro bundler via a public URL so a physical device or simulator can reach the dev server from inside the devcontainer. Use `--localhost` instead if running on a local machine without devcontainer networking constraints.

**`scripts/stop.sh`**
```bash
#!/usr/bin/env bash
pkill -f "uvicorn app.main" || true
pkill -f "celery -A tasks worker" || true
pkill -f "expo start" || true
pkill -f "next dev" || true
```

**`scripts/reset-db.sh`**
```bash
#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "$0")/stop.sh"
PGPASSWORD=probate psql -h localhost -U probate -d postgres \
  -c "DROP DATABASE IF EXISTS probate;" \
  -c "CREATE DATABASE probate;"
redis-cli FLUSHALL
uv run alembic upgrade head
uv run python -m scripts.seed
echo "Done. Run scripts/start.sh to start the app."
```

**`scripts/generate-types.sh`** — regenerate frontend TypeScript types from FastAPI OpenAPI spec
```bash
#!/usr/bin/env bash
# Requires running API; exports spec then generates TS types
curl -s http://localhost:8000/openapi.json > docs/openapi.json
pnpm dlx openapi-typescript docs/openapi.json -o packages/shared-types/src/api.ts
```

### Workflow
```
Host machine:
  bash scripts/devpod-setup.sh     # provision once

Inside devpod (automatic on start):
  uv sync, pnpm install, alembic upgrade head, seed

Development:
  bash scripts/start.sh            # start everything
  bash scripts/stop.sh             # stop everything
  bash scripts/reset-db.sh         # full data reset
  bash scripts/generate-types.sh   # sync TS types from FastAPI schema
```

---

## DocRouter Contract

`services/api` and `services/worker` build against this interface. For MVP, DocRouter is replaced with an MSW mock server.

**Submit screening job**
```
POST {DOCROUTER_API_URL}/jobs/screening
Body: { profile_id: str, documents: [{ url: str, type: str }] }
Response: { job_id: str, status: "queued" }
```

**Submit extraction job**
```
POST {DOCROUTER_API_URL}/jobs/extraction
Body: { profile_id: str, documents: [{ url: str, type: str }] }
Response: { job_id: str, status: "queued" }
```

**Get job status**
```
GET {DOCROUTER_API_URL}/jobs/{job_id}
Response: { job_id: str, status: "queued"|"processing"|"completed"|"failed", result?: dict }
```

**Webhook payload (POST /api/webhooks/docrouter)**
```json
{
  "event": "job.completed" | "job.failed",
  "job_id": "string",
  "job_type": "screening" | "extraction",
  "status": "completed" | "failed",
  "result": {
    "missing_documents": [...],
    "detected_documents": [...],
    "quality_issues": [...]
  }
}
```
Webhook signature: HMAC-SHA256 of request body, key = `DOCROUTER_WEBHOOK_SECRET`, header `X-DocRouter-Signature`.

---

## Environment Variables

```bash
# Database / Queue / Auth
DATABASE_URL              # postgresql+asyncpg://user:pass@host:5432/probate
REDIS_URL                 # redis://localhost:6379/0
JWT_SECRET_KEY            # 32-byte random string for JWT signing
JWT_ALGORITHM             # HS256
ACCESS_TOKEN_EXPIRE_MINUTES # default: 60

# S3-Compatible Storage
S3_ENDPOINT_URL
S3_REGION
S3_BUCKET_DOCUMENTS
S3_BUCKET_PETITIONS
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY

# DocRouter
DOCROUTER_API_URL
DOCROUTER_API_KEY
DOCROUTER_WEBHOOK_SECRET

# Celery
CELERY_WORKER_CONCURRENCY   # default: 4
CELERY_SCREEN_CONCURRENCY   # per-queue override for screening
CELERY_EXTRACT_CONCURRENCY  # per-queue override for extraction

# applicant-mobile (in app.config.js extra or .env via expo-constants)
EXPO_PUBLIC_API_URL       # e.g. https://<tunnel>.ngrok.io or http://localhost:8000

# admin-web (in .env.local)
NEXT_PUBLIC_API_URL       # e.g. http://localhost:8000
NEXTAUTH_SECRET
NEXTAUTH_URL

# EAS Build (for App Store / Play Store distribution)
EXPO_TOKEN                # EAS CLI authentication token

LOG_LEVEL                 # debug|info|warning|error
```

---

## Phase 0 — Foundation

**Goal:** Full project scaffold, Python and JS environments, DB schema, auth, storage, DevPod working end-to-end.

### Python stack decisions
- **`uv`** for Python package management (fast, modern, supports workspaces)
- **SQLAlchemy 2.x async** with `asyncpg` driver
- **Alembic** for migrations
- **Pydantic v2** for schemas (FastAPI default)
- **`python-jose`** for JWT, **`passlib[bcrypt]`** for password hashing

### Tasks
1. Write `docker-compose.dev.yml` for postgres, redis, minio sidecars (used from inside the DevPod)
2. Write `scripts/devpod-setup.sh`, `start.sh`, `stop.sh`, `reset-db.sh`, `generate-types.sh`
3. Init pnpm workspace with `pnpm-workspace.yaml` listing `apps/*` and `packages/*`; add `turbo.json` for frontend apps only
4. Add root `tsconfig.base.json` (strict, `moduleResolution: bundler`)
5. Scaffold `apps/applicant-mobile` as an Expo (React Native) app: `npx create-expo-app applicant-mobile --template blank-typescript`; add `app.json`, `eas.json`
5b. Scaffold `apps/admin-web` as a Next.js 15 App Router project
6. Scaffold `services/api` as a FastAPI app: `pyproject.toml`, `app/main.py`, `app/core/config.py`, `app/core/database.py`
7. Scaffold `services/worker` as a Celery app: `pyproject.toml`, `tasks/__init__.py`
8. Set up `uv` workspaces: root `pyproject.toml` referencing `services/api` and `services/worker` as workspace members
9. Copy architecture spec to `docs/architecture.md`
10. Write all SQLAlchemy models in `services/api/app/models/`:
    - `User`, `Case`, `CaseDocument`, `JurisdictionProfile`
    - `ScreeningRun`, `ExtractionRun`, `GeneratedPetition`
11. Write Alembic initial migration; run `alembic upgrade head`; verify all tables created
12. Write `app/core/storage.py`: `upload_object`, `get_presigned_url`, `delete_object` using `boto3`
13. Write `app/routers/auth.py`: `POST /auth/token` (OAuth2 password flow) returning JWT; `GET /auth/me`
14. Write `app/core/auth.py`: `get_current_user`, `require_role(role)` dependency
15. Write `scripts/seed.py`: one user per role, hardcoded PR jurisdiction profile stub
16. Add `packages/shared-types/` as a placeholder; `generate-types.sh` will populate it from the OpenAPI spec

### Key Files
- `docker-compose.dev.yml`
- `scripts/` — all four scripts
- `services/api/app/models/*.py`
- `services/api/app/core/config.py`, `database.py`, `auth.py`, `storage.py`
- `services/api/app/routers/auth.py`
- `services/api/alembic/versions/001_initial.py`
- `scripts/seed.py`

### Acceptance Criteria
- `bash scripts/devpod-setup.sh` provisions a working devpod
- `start.sh` brings up API at `localhost:8000`, Expo Metro bundler, admin web, and worker
- `reset-db.sh` drops all data and leaves the app in a clean seeded state
- `GET http://localhost:8000/docs` renders the FastAPI OpenAPI UI with all routes listed
- `POST /auth/token` with valid credentials returns a JWT
- `require_role('admin')` rejects an applicant token with 403
- `alembic upgrade head` creates all tables

---

## Phase 1 — Applicant Mobile App

**Goal:** Applicants can register, log in, create a case, scan documents with the native camera, upload them, and see a live checklist — on iOS and Android.

> **Phase 1 / Phase 2 dependency:** The requirements endpoint needs jurisdiction data. Phase 1 uses a **hardcoded stub** in the FastAPI router (the seeded PR profile). Phase 2 replaces it with real YAML-driven DB lookup. Phases can run in parallel.

### Key libraries
- `expo-camera` — native camera access and document capture
- `expo-image-manipulator` — crop, rotate, compress captured images
- `expo-file-system` + `expo-document-picker` — file upload from device storage
- `expo-secure-store` — store JWT securely (never AsyncStorage for tokens)
- `expo-notifications` — push notification registration and display
- `@tanstack/react-query` — API data fetching, polling, caching
- `react-hook-form` + `zod` — form validation

### Tasks
1. Install and configure dependencies: `expo-camera`, `expo-secure-store`, `expo-notifications`, `@tanstack/react-query`
2. Implement JWT auth: `POST /auth/token` → store token in `expo-secure-store` → inject as `Authorization: Bearer` header on all requests
3. Build login and register screens
4. API: `POST /cases` — create `Case` row with status `draft`, return case id
5. API: `GET /cases/{id}` — return case + documents + checklist status
6. API: `GET /cases` — paginated list for current user's cases
7. API: `GET /jurisdictions/{state}/{case_type}/requirements` — **stub in Phase 1**; returns required document types
8. Build case creation flow: state/county picker → case type → decedent info → submit
9. Build `DocumentScanner` screen: use `expo-camera` to capture document photo; `expo-image-manipulator` for crop/rotate; preview with re-capture option; assemble multi-page captures into a single upload
10. Upload flow: `POST /documents/presigned-url` → upload image/PDF directly to S3 → `POST /documents` registers `CaseDocument` row, enqueues Celery `screen_document` task
11. Build `DocumentChecklist` component: required types with status badges (uploaded / missing / pending / passed / rejected); poll `GET /cases/{id}` every 10s via React Query
12. Show rejection reason inline on rejected documents
13. Register device for push notifications (`expo-notifications`); store push token via `POST /devices/push-token`
14. After Phase 0 API is stable, run `generate-types.sh` and commit generated `packages/shared-types/src/api.ts`

### Key Files
- `apps/applicant-mobile/app/` — Expo Router screens: `(auth)/login`, `(auth)/register`, `(app)/cases/index`, `(app)/cases/[id]`, `(app)/cases/[id]/upload`
- `apps/applicant-mobile/components/DocumentScanner.tsx`
- `apps/applicant-mobile/components/DocumentChecklist.tsx`
- `apps/applicant-mobile/lib/api.ts` — typed fetch client using generated types
- `apps/applicant-mobile/lib/auth.ts` — JWT storage + refresh logic
- `services/api/app/routers/cases.py`
- `services/api/app/routers/documents.py`
- `services/api/app/routers/jurisdictions.py`

### Acceptance Criteria
- Login with seeded applicant credentials → JWT stored in `expo-secure-store` → authenticated API calls succeed
- Case creation persists a `Case` row with status `draft`
- Camera opens natively on iOS and Android; captured image previews correctly with re-capture option
- Document upload creates a `CaseDocument` row with S3 `storage_key`
- Checklist correctly shows required types from the stub profile
- Push notification token is registered on device and stored via API
- App runs on both iOS Simulator and Android Emulator via `expo start`

---

## Phase 2 — Jurisdiction Profiles

**Goal:** Jurisdiction rules loaded from YAML, seeded to DB, exposed via API. Replaces Phase 1 stub.

**Versioning:** Each profile version is a separate row in `jurisdiction_profiles` keyed by `(state_code, case_type, version)`. The seeder inserts a new row on content change; old rows are never updated.

### Tasks
1. Define Pydantic schema for jurisdiction profile YAML in `services/api/app/schemas/jurisdiction.py`
2. Write `services/jurisdiction_profiles/profiles/PR/declaratoria_de_herederos.yaml`
3. `loader.py`: read YAMLs from `profiles/` dir, validate against Pydantic schema, return typed objects
4. `seeder.py` (or add to `scripts/seed.py`): insert new version row on content change; never update
5. API: `GET /jurisdictions` — list available state/case_type combos (latest versions)
6. API: `GET /jurisdictions/{state}/{case_type}` — full profile (admin+); accepts `?version` param
7. API: `POST /jurisdictions` — super_admin only, accepts YAML payload, validates, inserts new version
8. Replace Phase 1 stub in requirements endpoint with DB-backed lookup

### Key Files
- `services/jurisdiction_profiles/profiles/PR/declaratoria_de_herederos.yaml`
- `services/api/app/routers/jurisdictions.py`
- `services/api/app/services/jurisdiction_loader.py`

### Acceptance Criteria
- Seeder inserts PR profile as version 1; re-run with changed YAML inserts version 2; version 1 preserved
- Schema validation rejects YAML missing `required_documents`
- Requirements endpoint returns DB data (stub removed)

---

## Phase 3 — DocRouter Integration & Worker

**Goal:** Async screening and extraction pipeline via Celery. Case transitions through state machine automatically.

**Idempotency:** All Celery tasks must be idempotent. `screen_document` checks for an existing `ScreeningRun` row for the same `case_document_id`; if found, skips submission. `poll_screening_job` and `poll_extraction_job` use `INSERT ... ON CONFLICT DO UPDATE`. `start_extraction` checks for an existing `ExtractionRun` before submitting.

**DocRouter for MVP:** Replaced by an MSW mock HTTP server during development and testing.

### Tasks
1. `services/api/app/services/docrouter_client.py`: typed `httpx` async client — `submit_screening_job`, `submit_extraction_job`, `get_job_status`, `get_job_result`. Exponential backoff, typed exceptions
2. `services/api/app/services/case_machine.py`: pure `transition_case(status, event) → CaseStatus | raise InvalidTransition`; covers all 11 states
3. `services/worker/tasks/screen_document.py`: Celery task — idempotency check → fetch presigned URL → `submit_screening_job` → upsert `ScreeningRun` → update `CaseDocument.screening_status = in_progress`
4. `services/worker/tasks/poll_screening_job.py`: `get_job_status` → on complete upsert `ScreeningRun` + `CaseDocument.screening_status = passed|rejected`
5. When all required docs pass → `transition_case` to `ready_for_extraction` → enqueue `start_extraction`
6. `services/worker/tasks/start_extraction.py`: idempotency check → `submit_extraction_job` → insert `ExtractionRun`
7. `services/worker/tasks/poll_extraction_job.py`: on complete → store `canonical_case_json` → `transition_case` to `admin_review`
8. Celery beat schedule: every 30s poll all in-progress `ScreeningRun` and `ExtractionRun` rows
9. Webhook: `POST /webhooks/docrouter` — validate HMAC-SHA256, route to same update logic as poll tasks
10. Dead-letter queue (Celery failure callbacks); `GET /admin/failed-tasks` API endpoint
11. Integration tests for `docrouter_client` using `respx` (httpx mock library)

### Key Files
- `services/api/app/services/docrouter_client.py`
- `services/api/app/services/case_machine.py`
- `services/api/app/routers/webhooks.py`
- `services/worker/tasks/screen_document.py`, `poll_screening_job.py`, `start_extraction.py`, `poll_extraction_job.py`
- `services/worker/mocks/docrouter_mock.py` — mock HTTP server for dev/testing

### Acceptance Criteria
- Uploading a document enqueues a `screen_document` Celery task (visible in Flower)
- Re-enqueueing the same task does not create a duplicate DocRouter submission
- Mock DocRouter pass → `CaseDocument.screening_status = passed`
- Mock DocRouter reject → applicant checklist shows rejection reason
- All docs passing → case transitions to `ready_for_extraction`
- Extraction complete → case transitions to `admin_review`
- `transition_case` unit tests cover all valid and invalid transitions
- Webhook rejects invalid HMAC

---

## Phase 4 — Admin Web UI

**Goal:** Admins review cases and extraction data; lawyers download petitions.

### Tasks
1. Configure `apps/admin-web` with NextAuth calling FastAPI `/auth/token`; middleware enforces `admin|lawyer|super_admin`
2. Case queue page (`/cases`): paginated table, status filter, search, sort — `GET /admin/cases`
3. Case detail page (`/cases/:id`): metadata, status timeline, documents, extraction results
4. `DocumentViewer.tsx`: render PDF/image from presigned S3 URL
5. `ExtractionForm.tsx`: structured editable form from `canonical_case_json`; `PATCH /admin/cases/{id}/extraction` persists overrides
6. `ConflictWarnings.tsx`: highlight fields where two docs disagree
7. Case status transition → `POST /admin/cases/{id}/transition` (role-gated)
8. Petition generation trigger → `POST /admin/cases/{id}/generate-petition`
9. Petition download link (presigned URL) → `GET /admin/cases/{id}/petition`
10. Lawyer approve/request-changes → `finalized` or back to `admin_review`
11. Super admin jurisdiction management: list, upload YAML, compare versions
12. SSE endpoint `GET /admin/cases/{id}/events` for real-time status updates (FastAPI `EventSourceResponse`)

### Key Files
- `apps/admin-web/src/app/cases/page.tsx`
- `apps/admin-web/src/app/cases/[id]/page.tsx`
- `apps/admin-web/src/components/DocumentViewer.tsx`, `ExtractionForm.tsx`, `ConflictWarnings.tsx`
- `services/api/app/routers/admin.py`

### Acceptance Criteria
- Applicant token rejected with 403 on all `/admin/*` routes
- Document viewer renders S3 file via presigned URL
- Extraction override persists and is used in petition generation
- SSE pushes status change within 2s of transition

---

## Phase 5 — Petition Generation

**Goal:** Generate `.docx` petition from `docxtpl` template + extracted data; store in S3; make downloadable.

**Template ownership:** Templates are provided by jurisdiction owners (legal team) and stored in `services/petition_generator/templates/` (committed) or overridden in S3 under `templates/`. S3 takes precedence. The `template_key` in the jurisdiction profile pins to a specific version.

**Idempotency:** `generate_petition` task checks for an existing `GeneratedPetition` row for `(case_id, template_key, template_version)`. If `status = completed`, returns existing S3 key without regenerating.

### Tasks
1. Add `services/petition_generator/templates/PR/declaratoria_de_herederos_v1.docx` (Jinja-style `{{ variable }}` placeholders, provided by legal)
2. `services/petition_generator/engine.py`: `generate_petition(template_key, version, case_data: dict) -> bytes` — load template, render with `docxtpl`, return bytes
3. `services/petition_generator/field_mapper.py`: map `canonical_case_json` (+ overrides) → flat `dict` of template variables
4. `POST /admin/cases/{id}/generate-petition`: validate `ready_for_generation` state → load profile → enqueue `generate_petition` Celery task
5. `GET /admin/cases/{id}/petition`: return 15-min presigned S3 download URL
6. `services/worker/tasks/generate_petition.py`: idempotency check → call engine → upload `.docx` to S3 → upsert `GeneratedPetition` → `transition_case` to `petition_generated`
7. Unit tests for `field_mapper.py` with fixture `canonical_case_json`
8. Integration test: fixture data → engine → assert bytes non-empty + text content

### Key Files
- `services/petition_generator/engine.py`, `field_mapper.py`
- `services/petition_generator/templates/PR/declaratoria_de_herederos_v1.docx`
- `services/api/app/routers/admin.py` (generate + download endpoints)
- `services/worker/tasks/generate_petition.py`

### Acceptance Criteria
- Generated `.docx` opens without corruption in Microsoft Word
- All template placeholders replaced with fixture data values
- Triggering generation when case is not in `ready_for_generation` returns 400
- Triggering generation twice does not create a second S3 file
- `GeneratedPetition` row upserted; file present in MinIO `petitions/` bucket

---

## Phase 6 — Hardening & Production Readiness

**Goal:** Security, observability, notifications, E2E tests, Docker.

**E2E testing strategy:**
- **API + admin-web:** Playwright tests run against a full local docker-compose stack (`postgres + redis + minio + FastAPI + Celery`). DocRouter is replaced by a mock HTTP server started before the test suite.
- **Mobile app:** Detox (or Maestro) for E2E tests on iOS Simulator / Android Emulator, hitting the same local API stack.

### Tasks
1. Email notifications (`fastapi-mail` or `resend`): on `screening_failed`, case reaching `admin_review`, `petition_generated`
2. In-app notifications table + `GET /notifications`, `PATCH /notifications/{id}/read`
3. Push notifications via `expo-notifications` (already registered in Phase 1); send from worker via FCM/APNs using stored push tokens
4. Rate limiting on public API routes (`slowapi`)
5. All request bodies already validated by Pydantic; add explicit 422 error formatting middleware
6. `structlog` structured logging in API and worker; include `case_id`, `user_id` in context
7. File type/size validation before S3 presign: allow PDF/JPEG/PNG/TIFF; max 50MB
8. CORS configuration: whitelist admin-web origin; mobile app does not require CORS
9. Presigned URL scoping: validate requesting user owns the case before issuing URL
10. RBAC audit: enumerate all routes, verify `require_role` dependencies
11. `GET /health`, `GET /health/db`, `GET /health/redis`
12. Playwright E2E (admin-web + API): register → create case → upload → screening (mock) → admin review → petition → lawyer download
13. Detox or Maestro E2E (mobile): login → create case → scan document → verify checklist update
14. `Dockerfile` for `services/api` and `services/worker`; extend `.devcontainer/docker-compose.yml` with `api` and `worker` services for production-like local testing
15. EAS Build configuration (`eas.json`) for App Store and Play Store distribution

---

## End-to-End MVP Verification

1. `bash scripts/devpod-setup.sh` — provision devpod (first time only; migrations + seed run automatically)
2. Inside devpod: `bash scripts/start.sh` — MinIO buckets created, API at `localhost:8000`, Expo Metro at `localhost:8081`, admin web at `localhost:3002`, Celery worker running
3. **Applicant (mobile)**: open Expo Go on device or simulator → scan QR from Metro → register → create PR/declaratoria case → scan/upload fixture documents → verify checklist updates
4. **Worker**: observe `screen_document` tasks in Flower (`localhost:5555`); mock DocRouter passes all docs; case transitions to `ready_for_extraction` → `admin_review`
5. **Admin**: log in → open case → view documents + extraction data → override a field → transition to `ready_for_generation` → generate petition
6. **Lawyer**: log in → download `.docx` → verify fields populated → approve → case = `finalized`
7. **Push notification**: verify applicant device receives notification when case status changes

---

## Phase Sequencing

```
Phase 0: Foundation          — FastAPI scaffold, DB, Auth, Storage, DevPod  (prerequisite for all)
Phase 1: Applicant Mobile    — Expo app, native camera, upload, checklist    (after Phase 0; stub requirements)
Phase 2: Jurisdiction Data   — YAML profiles, seeding                        (after Phase 0; parallel with Phase 1)
Phase 3: DocRouter + Celery  — Screening, extraction, state machine          (after Phase 2)
Phase 4: Admin Web UI        — Queue, review, conflict detection             (after Phase 3)
Phase 5: Petition Gen        — docxtpl engine, generation                    (after Phase 4)
Phase 6: Hardening           — Notifications, security, E2E, Docker         (incremental, intensifies at end)
```
