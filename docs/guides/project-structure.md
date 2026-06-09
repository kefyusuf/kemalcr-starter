# Project Structure

## Top-Level Directories

- `src/` application source
- `spec/` tests and test support
- `db/` SQL migrations and seeds
- `openapi/` contract files
- `docs/` architecture, guides, and roadmap material
- `docker/` container build assets
- `scripts/` developer entrypoints

## Source Layout

### `src/core/`

Cross-cutting platform concerns:

- config
- HTTP request context
- structured error handling
- idempotency service
- security defaults
- request logging support objects
- authentication and tenancy handlers

### `src/infrastructure/`

Technology-facing adapters:

- PostgreSQL connection management
- Redis connection management
- migration runner
- repository base classes
- JWT token provider
- password hashing and API key secret hashing

### `src/modules/`

Business-facing modules currently include:

- `identity/` for login, refresh, logout, `/v1/me`, active organization switching, and auth throttling
- `organizations/` for tenant-aware organization reads and writes, memberships, and invitations
- `api_keys/` for organization-scoped key management and machine authentication

### Entry Points

- `src/app.cr` starts the HTTP application
- `src/migrate.cr` runs migration actions
- `src/kemalcr_starter.cr` wires settings, handlers, services, and routes together

## Test Layout

### `spec/requests/`

HTTP-level request specs.

### `spec/integration/`

Cross-request or multi-step flow validation such as refresh rotation and API key authentication.

### `spec/infrastructure/`

Repository and infrastructure-oriented tests.

### `spec/support/`

Reusable test helpers for PostgreSQL and Redis.

## Database Layout

### `db/migrations/`

SQL migration files using paired naming:

- `NNN_name.up.sql`
- `NNN_name.down.sql`

### `db/seeds/`

Reserved for future seed data.

## Design Intent

The project keeps platform core, infrastructure adapters, and domain modules separate so future e-commerce, CMS, or SaaS features can be added without rewriting the foundation.

The current implementation prefers explicit service and repository wiring over hidden magic. That keeps the codebase easier to audit, easier to document, and more approachable for extension into later product modules.
