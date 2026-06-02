<!-- GSD:project-start source:PROJECT.md -->
## Project

**Kemalcr API Platform**

A multi-tenant API platform foundation built with Crystal and Kemal. Provides tenant-aware identity, organization management, API key authentication, idempotent writes, and rate limiting as reusable primitives. Designed as a shared kernel that e-commerce, CMS, SaaS, and similar products can build on without reinventing auth, tenancy, or common infrastructure.

**Core Value:** Modules evolve independently through a shared kernel — no module depends on another, all share the same core infrastructure.

### Constraints

- **Language**: Crystal 1.12+ — all new code in Crystal
- **Framework**: Kemal 1.11 — no framework migration
- **Database**: PostgreSQL 16 — no additional database engines
- **Cache**: Redis 7 — available for pub/sub and transient state
- **Architecture**: Modular monolith — no service split
- **Event reliability**: Outbox pattern required — no at-most-once delivery
- **Testing**: spec-kemal request tests + repository tests — existing patterns
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Crystal 1.17.1+ (requires `>= 1.12.0` per `shard.yml`) - All application source code in `src/`
- SQL (PostgreSQL dialect) - Database migrations in `db/migrations/`
- YAML - OpenAPI contract `openapi/openapi.yaml`
## Runtime
- Docker-first development and CI; production runs single Alpine-based statically-linked binary
- Base image: `crystallang/crystal:1.17.1-alpine` (`docker/app/Dockerfile`)
- Runtime image: `alpine:3.20` with `gc gmp libgcc libstdc++ pcre2 tzdata`
- Shards (Crystal native) - Lockfile `shard.lock` present and committed
## Frameworks
- Kemal 1.11.0 (`kemalcr/kemal`) - HTTP framework, routing, middleware pipeline, server lifecycle
- Kemal v1.11.0 is locked in `shard.lock`
- Crystal Spec (built-in) - Test runner without external assertion library
- `spec-kemal` 1.3.0 (`kemalcr/spec-kemal`) - Kemal-specific request testing helpers; development dependency only
- `crystal tool format` - Built-in formatter (enforced in CI via `scripts/lint`)
- Docker Compose V2 - Local development, CI pipelines, runtime smoke tests
## Key Dependencies
| Shard | Version | Purpose | Source |
|-------|---------|---------|--------|
| `kemal` | 1.11.0 | HTTP server, routing, middleware | `github: kemalcr/kemal` |
| `pg` | 0.29.0 | PostgreSQL driver | `github: will/crystal-pg` |
| `redis` | 0.15.3 | Redis client for throttling, idempotency locks | `github: jgaskins/redis` |
| `jwt` | 1.7.1 | JWT signing/verification (HS256) | `github: crystal-community/jwt` |
| Shard | Version | Purpose |
|-------|---------|---------|
| `db` | 0.13.1 | Crystal database abstraction layer (crystal-db) |
| `backtracer` | 1.2.4 | Pretty error backtraces in Kemal |
| `exception_page` | 0.5.0 | Dev-mode error page rendering |
| `radix` | 0.4.1 | Tree-based URL routing (Kemal dependency) |
- `Crypto::Bcrypt::Password` - Password hashing in `src/infrastructure/crypto/password_hasher.cr`
- `Digest::SHA256` - Token fingerprinting (`token_fingerprint.cr`) and API key secret hashing (`api_key_secret_hasher.cr`)
- `UUID` - ID generation throughout all services
- `JSON::Serializable` - Request/response struct marshalling
- `HTTP::Server::Context` - Direct access to raw HTTP context in handlers
## Configuration
- All configuration is through environment variables; no config files (JSON/YAML/TOML)
- See `src/core/config/settings.cr` for the canonical `Settings` record
- `.env.example` documents all 23 env vars with defaults
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection string
- `JWT_SECRET` - HMAC signing key (must be changed in production)
- `PASSWORD_PEPPER` - Pre-hash password salt (must be changed in production)
- `BCRYPT_COST` - Password hashing cost (default 10, lowered to 4 in test)
- Multi-stage Docker build: `base` (shards install) -> `dev` (source mount) -> `build` (production binary) -> `runtime` (Alpine minimal)
- `shards install --production` for production builds
- Build args: `APP_VERSION`, `APP_BUILD_TIME`, `APP_GIT_SHA` injected during release build
## Platform Requirements
- Docker Engine with Compose V2 plugin
- Port 3000 available for the application
- Docker host or container orchestrator
- PostgreSQL 16 (matching `postgres:16-alpine`)
- Redis 7 (matching `redis:7-alpine`)
## Developer Scripts
- `docker compose up --build app postgres redis` - Full dev stack startup
- Volumes: `shards-cache`, `crystal-cache` for fast reinstall
- `docker compose run --rm app sh -lc "shards install && crystal tool format --check src spec"`
- `docker compose run --rm -e KEMAL_ENV=test app sh -lc "shards install && crystal run src/migrate.cr -- up && crystal spec"`
- `docker compose run --rm app sh -lc "crystal run src/migrate.cr -- up|down|reset|status"`
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- `snake_case.cr` for all source and spec files (e.g., `auth_service.cr`, `user_repository.cr`, `system_spec.cr`)
- File names mirror the primary class/module name (e.g., `api_error.cr` contains `ApiError`, `connection_manager.cr` contains `ConnectionManager`)
- PascalCase for module hierarchy, nested 3 levels deep: `KemalcrStarter::ModuleName::SubModule`
- Root namespace is `KemalcrStarter` (declared in `src/kemalcr_starter.cr`)
- PascalCase for all class names (e.g., `AuthService`, `PasswordHasher`, `UserRepository`, `ApiError`)
- Abstract classes use the same convention (e.g., `AuthThrottle`, `Repository`)
- PascalCase for Crystal `record` declarations (e.g., `UserRecord`, `AccessTokenClaims`, `TokenPairResponse`)
- Records defined close to their using class (e.g., `UserRecord` in `user_repository.cr`)
- PascalCase for `struct` types (e.g., `LoginRequest`, `RefreshRequest`, `Settings`)
- Used for JSON deserialization in route modules only
- `snake_case` for all method names (e.g., `login`, `find_credentials_by_email`, `serialize_organization`)
- Bang methods (`!`) only for methods that can raise exceptions (e.g., `check!`, `migrate!`, `truncate_all!`, `validate_login_request!`)
- Predicate methods use `?` suffix (e.g., `ready?`, `can_manage_organization?`)
- `snake_case` for local variables and method parameters (e.g., `normalized_email`, `access_token`, `refresh_token_hash`)
- Instance variables use Crystal's `@` prefix and snake_case (e.g., `@database`, `@settings`, `@password_hasher`)
- `UPPER_SNAKE_CASE` for constants (e.g., `ALGORITHM = JWT::Algorithm::HS256`, `LOCK_TTL = 30.seconds`)
- PascalCase with single capital letter for generic types: `forall T`
## Code Style
- Uses `crystal tool format --check src spec` via `scripts/lint`
- The project enforces Crystal's canonical formatter (no `.editorconfig` at project root)
- CI pipeline runs format check in `.github/workflows/ci.yml` step "Run format check"
- 2-space indentation (Crystal default)
- No trailing whitespace
- Consistent spacing around operators and braces
- Hash literals aligned by convention:
- No hard limit observed; most lines fit within ~100 characters
- Long method chains and SQL heredocs use indented continuation:
- No dedicated linter beyond `crystal tool format`
- Crystal's built-in type checker catches type errors at compile time
- `--error-trace` used in CI for verbose error reporting
## Import Organization
- No path aliases used. All requires use relative paths from the requiring file to the target file.
- `src/kemalcr_starter.cr` acts as the central manifest, listing all internal requires in a defined order:
## Error Handling
- Domain errors are raised through the `ApiError` hierarchy defined in `src/core/errors/api_error.cr`
- Always use the typed error classes rather than generic `Exception`:
- Catch clauses use the typed error for domain logic and `::DB::Error` for database constraint violations:
- `ErrorHandler` middleware in `src/core/errors/error_handler.cr` catches all exceptions:
## Logging
- Used sparingly; only for unexpected/unhandled exceptions
- Structured key=value format in log messages:
- No debug or info level logging observed in production code paths
## Comments
- Minimal comments; code is mostly self-documenting
- Comments used only for non-obvious intent (e.g., fail-open rationale in `auth_throttle.cr`)
- No JSDoc or TSDoc-style docstrings observed
- No inline comments on obvious code
## Function Design
- Methods typically fit within 5-20 lines
- Service methods (e.g., `login`, `refresh`) are larger (~30-50 lines) due to sequential business logic
- Named parameters with `*` for constructors with multiple optional parameters:
- Return type annotations `: Nil`, `: Bool`, `: String` on all methods
- Parameter type annotations always included
- `Nil` return type for void methods (side-effect only)
- Named tuples (`{key: value}`) for serialized responses (not full structs)
- `?` type union (e.g., `String?`) for nullable returns
- `not_nil!` used when the developer knows a value cannot be nil at runtime:
- `check!` for AuthThrottle because it raises on limit exceeded
- `migrate!`, `truncate_all!`, `clear!` for test setup because they perform destructive operations
## Module Design
- All types are public within their namespace; no explicit `private` module-level declarations
- Individual methods use `private` keyword for internal helpers
- `protected` used in abstract base classes for methods accessible to subclasses:
- `src/kemalcr_starter.cr` is the single barrel file; requires all internal files in dependency order
- `src/app.cr` is the entry point: requires the barrel and boots the app
- Lazy singleton services registered via class methods on `KemalcrStarter::App` (e.g., `self.auth_service`)
- `@@class_var` for the singleton instance
- `reset_services` for test isolation (clears all singleton class variables)
- Route modules use `extend self` for module-level methods
- `draw` method registers all routes via `get`, `post`, `patch`, `delete` Kemal DSL
- Route modules define inline `struct` types for JSON request deserialization
- Private helper methods for request parsing (e.g., `parse_json_body`, `extract_bearer_token`, `ip_address`)
- Repository classes inherit from `KemalcrStarter::Infrastructure::DB::Repository`
- Accept `::DB::Database | ::DB::Connection` for transaction support
- SQL heredocs with `$1` parameterized queries
- Private record types for row mapping defined alongside repository classes
- Service classes accept `@settings` and `@database` via constructor injection
- Methods correspond to use cases; return serialized named tuples or typed objects
- Authorization checks inline at method start (guard clauses)
- Database transactions wrap multi-table writes
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- Three-layer separation: `core/` (cross-cutting platform logic), `infrastructure/` (technology-facing adapters), `modules/` (business domain logic)
- Session-oriented JWT authentication with rotating refresh tokens
- Organization-aware tenancy scoped via access token claims
- Explicit service-repository wiring (no ORM, no DI framework — raw SQL through a Repository base class)
- Idempotent writes on selected POST endpoints using Redis locks + PostgreSQL persistence
- Docker-first local development with PostgreSQL 16 and Redis 7
- Contract-first: OpenAPI YAML at `openapi/openapi.yaml` serves as source of truth exposed at `/openapi`
## Layers
- Purpose: Cross-cutting platform concerns that have no business domain knowledge
- Location: `src/core/`
- Contains: Config (`config/settings.cr`), HTTP request context (`http/request_context.cr`, `http/request_context_handler.cr`), structured error base classes (`errors/api_error.cr`, `errors/error_handler.cr`), idempotency service (`idempotency/service.cr`), security headers handler (`security/security_headers_handler.cr`), auth/tenancy handlers (`tenancy/authentication_handler.cr`), request log context (`logging/request_log_context.cr`)
- Depends on: Kemal framework, standard library (UUID, Digest, JSON)
- Used by: All modules via `App` composition class
- Purpose: Technology-facing adapters that encapsulate external systems (PostgreSQL, Redis, JWT, crypto)
- Location: `src/infrastructure/`
- Contains: DB connection management (`db/connection_manager.cr`), abstract Repository base class (`db/repository.cr`), repository implementations for all entities, migration runner (`db/migrator.cr`), Redis client manager (`redis/client_manager.cr`), JWT token provider (`jwt/token_provider.cr`), crypto utilities for password hashing, API key secret hashing, token fingerprinting (`crypto/`)
- Depends on: PG driver, Redis driver, JWT shard, Crystal crypto/stdlib
- Used by: Core layer (idempotency service) and all module services
- Purpose: Business domain modules — each module contains routes and a service class
- Location: `src/modules/`
- Contains: `identity/` (auth routes, auth service, auth throttle, me routes, me service), `organizations/` (organization routes, organization service), `api_keys/` (API key routes, API key service)
- Depends on: Core layer (errors, request context, idempotency, settings), Infrastructure layer (repositories, crypto, JWT)
- Used by: `KemalcrStarter::App.boot` via route registration
- Purpose: Wires everything together — settings, middleware, services, routes — as class-level singletons on `KemalcrStarter::App`
- Location: `src/kemalcr_starter.cr`
- Contains: `App.boot` method that calls `configure` (middleware chain) and `draw_routes` (system + module routes); lazy-loaded service singletons (`auth_service`, `api_key_service`, `idempotency_service`, `me_service`, `organization_service`)
- Depends on: All layers — requires every `.cr` file in the project
- Entry points: `src/app.cr` (HTTP server) and `src/migrate.cr` (standalone migration runner)
## Middleware Pipeline
## Request Lifecycle
## Module Boundaries and Dependency Direction
```
```
- Modules never import each other — cross-module data flow happens through `App` composition
- Each module owns its service class and one `*Routes.draw` method
- Services compose repositories from `infrastructure/db/` and crypto/JWT from `infrastructure/crypto/` and `infrastructure/jwt/`
- `AuthService` is the single source of truth for token handling — it serves both `auth_routes` and `authentication_handler`
## Data Flow
## State Management
- Service instances are class-level `@@` variables on `KemalcrStarter::App` — lazy-loaded singletons
- `reset_services` sets all `@@` vars to nil (used in test setup for isolation)
- DB connections are module-level `@@` singletons in `ConnectionManager` and `ClientManager` — re-created if database_url changes
- `RequestContext` is a Crystal `record` stored in Kemal's per-request env hash under `"request_context"`
- `add_context_storage_type(KemalcrStarter::Core::Http::RequestContext)` enables type-safe storage
- Authentication handler replaces the initial RequestContext with an enriched version (actor_id, etc.)
- Route handlers retrieve via `App.request_context(env)`
- PostgreSQL tables: `users`, `user_sessions`, `organizations`, `organization_memberships`, `api_keys`, `idempotency_keys`
- Redis: auth throttle counters (fixed-window buckets), idempotency locks (short-lived, `nx` key with 30s TTL)
## Error Handling Strategy
- `Core::Errors::ApiError` is an abstract class extending `Exception` with `code`, `status_code`, and `details` fields
- Concrete error subclasses: `UnauthorizedError` (401/AUTH_UNAUTHORIZED), `ForbiddenError` (403/AUTH_FORBIDDEN), `ValidationError` (422/VALIDATION_ERROR), `ConflictError` (409/REQUEST_CONFLICT), `TooManyRequestsError` (429/RATE_LIMITED)
- `ErrorHandler` middleware catches `ApiError` → maps to JSON; catches any other `Exception` → 500/INTERNAL_SERVER_ERROR (no stack leak)
- All error responses include `error.request_id` matching the `X-Request-Id` header
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
