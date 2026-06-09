# Kemal API Foundation

Docker-first API foundation built with Kemal, Crystal, PostgreSQL, and Redis.

This repository is structured as an API-first starter that can be reused under an ecommerce product, a CMS, or a SaaS application. The current implementation already covers tenant-aware identity, organization management, selected idempotent write flows, and API key management.

## Implemented Capabilities

- system endpoints: `/health`, `/ready`, `/version`, `/openapi`
- JWT login, refresh rotation, logout, and logout-all
- Redis-backed fixed-window throttling for login and refresh
- `GET /v1/me` and active organization switching
- organization create, list, detail, and update
- membership listing and invitation create, list, accept, and revoke
- selected idempotency support for organization create, invitation create, auth refresh, and API key create
- API key create, list, revoke, and first machine-authenticated read access
- OpenAPI contract stored in `openapi/openapi.yaml`

## Stack

- Crystal
- Kemal
- PostgreSQL
- Redis
- Docker Compose

## Prerequisites

- Docker
- Docker Compose

## Quick Start

Start the development stack:

```sh
./scripts/dev
```

Wait for the app to boot on `http://localhost:3000`, then verify the base endpoints:

```sh
curl http://localhost:3000/health
curl http://localhost:3000/ready
curl http://localhost:3000/version
curl http://localhost:3000/openapi
```

## Validation Commands

Run the format check:

```sh
./scripts/lint
```

Run the test suite inside Docker:

```sh
./scripts/test
```

Run migrations manually:

```sh
./scripts/migrate up
./scripts/migrate status
./scripts/migrate reset
```

## Authentication Modes

### Human authentication

- Bearer JWT access tokens protect the actor-centric endpoints.
- Refresh tokens rotate persisted sessions.
- Tenant context is carried through the active organization claim.

### Machine authentication

- `X-API-Key` is supported for organization-scoped machine access.
- The current machine-authenticated read surface includes:
- `GET /v1/organizations/:organization_id`
- `GET /v1/organizations/:organization_id/memberships`

## Project Layout

- `src/` application source
- `spec/` request, repository, and integration tests
- `openapi/` API contract source of truth
- `db/migrations/` PostgreSQL schema migrations
- `docker/` Docker image definitions
- `docs/` architecture notes, guides, roadmap, and specs
- `scripts/` Docker-first developer commands

## CI

GitHub Actions validation is defined in `.github/workflows/ci.yml`.

The workflow currently checks:

- Docker Compose configuration
- application image build
- Crystal format validation
- request and integration test suite
- OpenAPI YAML parsing
- release image build
- release container smoke test against PostgreSQL and Redis

## Documentation Map

- `docs/architecture/overview.md`
- `docs/architecture/authentication.md`
- `docs/architecture/error-model.md`
- `docs/architecture/tenancy-model.md`
- `docs/architecture/organizations.md`
- `docs/architecture/idempotency.md`
- `docs/guides/deployment.md`
- `docs/guides/local-development.md`
- `docs/guides/project-structure.md`
- `docs/roadmap/phase-8-readiness-audit.md`
- `docs/roadmap/implementation-plan.md`

## Current Status

The Phase 8 reusable-starter baseline is now in place, covering CI, release metadata, auth throttling, onboarding, deployment guidance, and a readiness audit. The roadmap source remains `docs/roadmap/implementation-plan.md`.
