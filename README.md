# Kemalcr Starter

Docker-first multi-tenant API platform built with **Crystal**, **Kemal**, **PostgreSQL**, and **Redis**.

Identity, organizations, API keys, RBAC, idempotent writes, an outbox event bus, outbound webhooks, and plug-and-play domain modules — so you can ship a B2B/SaaS API without reinventing auth and tenancy.

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

## Quick start (5 minutes)

**Prerequisites:** Docker with Compose v2.

```sh
git clone https://github.com/kefyusuf/kemalcr-starter.git
cd kemalcr-starter
./scripts/dev
```

That builds the app image and starts `app` + `postgres` + `redis` on port **3000**.

```sh
curl -s http://localhost:3000/health
curl -s http://localhost:3000/ready
curl -s http://localhost:3000/version
```

### Your first API calls

```sh
# 1) Register (password: min 8 chars, upper + lower + digit)
TOKEN=$(curl -s -X POST http://localhost:3000/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada","email":"ada@example.com","password":"Passw0rd!"}' \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

# 2) Create an organization
ORG=$(curl -s -X POST http://localhost:3000/v1/organizations \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Acme","slug":"acme"}')
ORG_ID=$(echo "$ORG" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

# 3) Create a product
curl -s -X POST "http://localhost:3000/v1/organizations/$ORG_ID/products" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"sku":"SKU-1","name":"Widget","price_cents":1999,"currency":"USD"}'

# 4) Create a webhook endpoint (secret is shown once)
curl -s -X POST "http://localhost:3000/v1/organizations/$ORG_ID/webhooks" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/hooks","description":"demo","event_types":[]}'
```

Or run the full golden path in one shot:

```sh
./examples/smoke.sh
```

### OpenAPI

- Live document: `GET http://localhost:3000/openapi`
- Source: [`openapi/openapi.yaml`](openapi/openapi.yaml)

### Tests & lint

```sh
./scripts/test    # full spec suite
./scripts/lint    # crystal tool format --check
```

## What you get

### System & observability
- `GET /health`, `GET /ready`, `GET /version`, `GET /openapi`
- Structured access logging (method, path, status, duration, actor_id, org_id)
- Outbox event system with background publisher, retry with backoff, dead letter queue
- Audit log handlers, event metrics, dead-letter admin endpoints

### Authentication
- `POST /v1/auth/register` with password policy (min 8, upper/lower/digit)
- `POST /v1/auth/login` with JWT access + refresh token pair
- `POST /v1/auth/refresh` with rotation and reuse detection (family revocation)
- `POST /v1/auth/logout`, `POST /v1/auth/logout-all`
- Redis-backed throttling (login, refresh, register)
- Machine auth via `X-API-Key`
- Password reset request/confirm (no user enumeration)

### Authorization (RBAC)
- Roles: owner, admin, member
- Permissions for organizations, API keys, webhooks, products
- Seed / list / manage role-permission assignments

### Organizations & memberships
- Create, list (paginated), detail, update
- Membership listing, invitations (create/list/accept/revoke)
- Active organization switch via `POST /v1/me/active-organization`

### API keys
- Create, list, revoke — org-scoped machine-to-machine auth
- Secret revealed only at creation

### Idempotency
- Selected POST endpoints honor `Idempotency-Key` (Redis lock + PostgreSQL fingerprint)

### Outbound webhooks (pluggable)
- Org-scoped endpoints and delivery, event-type filters (empty = all tenant-owned events)
- HMAC-SHA256 signed payloads (`X-Webhook-Signature: sha256=...`)
- Delivery ledger; failures retry via outbox, then dead-letter

### Products (pluggable module template)
- Org-scoped CRUD under `/v1/organizations/:id/products`
- Events: `product.created`, `product.updated`, `product.deleted`
- See [`docs/guides/adding-a-module.md`](docs/guides/adding-a-module.md)

### Billing (pluggable adapter)
- `BillingAdapter` port: `null` (default) and `stripe`
- `POST /v1/organizations/:id/billing/checkout`
- `POST /v1/billing/webhooks/stripe` — Stripe signature-verified receiver

### Cross-cutting
- CORS (`CORS_ORIGINS`), security headers, typed errors (401/403/409/422/429)
- Request correlation via `X-Request-Id`

## Configuration

Copy or edit env values from [`.env.example`](.env.example). Highlights:

| Variable | Purpose |
|----------|---------|
| `JWT_SECRET`, `PASSWORD_PEPPER` | **Change in production** |
| `ENABLED_MODULES` | `password_reset,webhooks,products,billing` |
| `EMAIL_ADAPTER` | `console` (default) or `smtp` |
| `BILLING_ADAPTER` | `null` (default) or `stripe` |
| `STRIPE_API_KEY`, `STRIPE_WEBHOOK_SECRET` | Stripe integration |

## Extending

- Add a domain module: [`docs/guides/adding-a-module.md`](docs/guides/adding-a-module.md)
- Architecture notes: [`docs/architecture/`](docs/architecture/)
- Local development: [`docs/guides/local-development.md`](docs/guides/local-development.md)

## Project layout

- `src/` — core/, infrastructure/, modules/
- `spec/` — request, integration, repository, unit tests
- `openapi/` — OpenAPI 3.1.0 contract
- `db/migrations/` — PostgreSQL migrations
- `docker/` — multi-stage Dockerfile
- `docs/` — architecture and guides
- `examples/` — runnable API scripts
- `scripts/` — dev, test, lint, migrate

## CI

GitHub Actions (`.github/workflows/ci.yml`): compose validation, image build, format check, full test suite, OpenAPI parse, release image smoke test.

## License

MIT — see [LICENSE](LICENSE).
