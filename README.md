# Kemalcr Starter

Docker-first multi-tenant API platform built with **Crystal**, **Kemal**, **PostgreSQL**, and **Redis**.

A production-minded shared kernel: identity, organizations, API keys, RBAC, idempotent writes, an outbox event bus, outbound webhooks, and plug-and-play domain modules — so you can ship a B2B/SaaS API without reinventing auth and tenancy.

**Why Crystal/Kemal?** Native speed, small static binary, Ruby-like syntax, and a simple fiber concurrency model. This starter packages the boring infrastructure so you can focus on your product module.

```text
┌─────────────────────────────────────────────────────────────┐
│                     HTTP (Kemal)                            │
├──────────────┬──────────────────────────────────────────────┤
│   core/      │ errors · RBAC · events · idempotency · HTTP  │
├──────────────┼──────────────────────────────────────────────┤
│   modules/   │ identity · organizations · api_keys          │
│              │ products · webhooks · billing (optional)     │
├──────────────┼──────────────────────────────────────────────┤
│ infrastructure/ │ email · billing · JWT · crypto · outbox   │
│                 │ Postgres · Redis adapters                 │
└──────────────┴──────────────────────────────────────────────┘
```

## Implemented Capabilities

### System & Observability
- `GET /health`, `GET /ready`, `GET /version`, `GET /openapi`
- Structured access logging (method, path, status, duration, actor_id, org_id)
- Outbox event system with background publisher, retry with backoff, dead letter queue
- Audit log handlers for all domain events (organization, membership, API key, user)
- Event metrics and dead letter management endpoints

### Authentication
- `POST /v1/auth/register` with password policy validation (min 8 chars, upper/lower/digit)
- `POST /v1/auth/login` with JWT access + refresh token pair
- `POST /v1/auth/refresh` with rotation and reuse detection (family revocation)
- `POST /v1/auth/logout`, `POST /v1/auth/logout-all`
- Redis-backed fixed-window throttling (login, refresh, register)
- Machine authentication via `X-API-Key` header

### Authorization (RBAC)
- Three built-in roles: owner, admin, member
- Permission enum covering organizations, API keys, webhooks, and products
- Owner gets all permissions, admin gets all except org delete, member gets read/list subset
- Endpoints to seed, list permissions, and manage role-permission assignments

### Current Actor
- `GET /v1/me` — authenticated actor profile with organization context
- `POST /v1/me/active-organization` — switch active organization, reissue tokens

### Organizations
- Create, list (paginated), detail, update
- Membership listing (paginated)
- Invitation create, list (paginated), accept, revoke
- RBAC-guarded write operations

### API Keys
- Create, list (paginated), revoke
- Organization-scoped machine-to-machine authentication
- Secret revealed only at creation

### Idempotency
- Selected POST endpoints: organization create, invitation create, auth refresh, API key create
- Redis lock + PostgreSQL persistence with fingerprint-based replay detection

### Password Reset (pluggable module)
- `POST /v1/auth/password-reset/request` — always 202, no user enumeration
- `POST /v1/auth/password-reset/confirm` — updates password, revokes all sessions
- Email delivery via swappable adapter (`EMAIL_ADAPTER=console|smtp`)
- One-time hashed tokens with configurable TTL (`PASSWORD_RESET_TTL_MINUTES`)

### Outbound Webhooks (pluggable module)
- Org-scoped endpoint CRUD under `/v1/organizations/:id/webhooks`
- Event-type filtering (empty list = all events)
- HMAC-SHA256 signed payloads (`X-Webhook-Signature: sha256=...`)
- Delivery ledger with per-endpoint attempt tracking
- Integrated with outbox publisher — failures retry with backoff, then dead-letter

### Products (pluggable module)
- Org-scoped catalog CRUD under `/v1/organizations/:id/products`
- SKU uniqueness per organization, RBAC (`product:manage` / `product:list`)
- Domain events: `product.created`, `product.updated`, `product.deleted`
- Template for adding new domain modules (see `docs/guides/adding-a-module.md`)

### Billing (pluggable adapter)
- `BillingAdapter` port with `null` (default) and `stripe` implementations
- `POST /v1/organizations/:id/billing/checkout` creates a provider checkout session
- Swap via `BILLING_ADAPTER=null|stripe` + `STRIPE_API_KEY`

### Plug-and-Play Modules
- `ENABLED_MODULES=password_reset,webhooks,products,billing` toggles optional modules
- Email adapter swap via `App.install_email_adapter` (console default)
- Billing adapter swap via `App.install_billing_adapter` (null default)
- Wildcard event handlers (`*`) for fan-out integrations

### Cross-Cutting
- CORS middleware with configurable origins (`CORS_ORIGINS`)
- Security headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
- Structured error responses with typed error classes (401/403/409/422/429)
- Request correlation via `X-Request-Id`

## Stack

- Crystal 1.17.1+
- Kemal 1.11.0
- PostgreSQL 16, Redis 7
- Docker Compose V2

## Quick Start

```sh
./scripts/dev
```

Verify:

```sh
curl http://localhost:3000/health
curl http://localhost:3000/ready
curl http://localhost:3000/version
```

## Testing

```sh
./scripts/test          # Run all specs (169 examples, 0 failures)
./scripts/lint          # Crystal format check
```

## Authentication Modes

### Human (Bearer JWT)
```
POST /v1/auth/register   {"name", "email", "password"}  → 201 + token pair
POST /v1/auth/login      {"email", "password"}          → 200 + token pair
```

### Machine (X-API-Key)
```
POST /v1/organizations/:id/api-keys  → 201 + secret (one-time)
GET  /v1/organizations/:id           → via X-API-Key header
GET  /v1/organizations/:id/memberships → via X-API-Key header
```

## Extending

- Add a domain module: [`docs/guides/adding-a-module.md`](docs/guides/adding-a-module.md)
- OpenAPI contract: `openapi/openapi.yaml`
- Smoke flow example: `./examples/smoke.sh`

## Project Layout

- `src/` — application source (core/, infrastructure/, modules/)
- `spec/` — request, integration, repository, and unit tests
- `openapi/` — OpenAPI 3.1.0 contract (openapi.yaml)
- `db/migrations/` — PostgreSQL migrations
- `docker/` — multi-stage Dockerfile (base → dev → build → runtime)
- `docs/` — architecture, guides, roadmap
- `examples/` — runnable API smoke script
- `scripts/` — dev, test, lint, migrate

## CI

GitHub Actions (`.github/workflows/ci.yml`):
- Docker Compose config validation
- Application image build
- Crystal format check
- Full test suite (request + integration + unit)
- OpenAPI YAML parsing
- Release image build and smoke test

## License

MIT — see [LICENSE](LICENSE).
