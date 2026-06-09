# Authentication Architecture

This project uses a session-oriented authentication model built on top of JWT access tokens and rotating JWT refresh tokens.

## Token Model

- Access tokens are short-lived bearer JWTs signed with `HS256`.
- Refresh tokens are also signed JWTs, but every refresh token maps to a persisted `user_sessions` row.
- The stored refresh token value is never persisted directly. The database stores a SHA-256 fingerprint derived from the token and the configured pepper.
- Organization API keys are stored with a visible prefix and a SHA-256 secret hash derived from the configured pepper.

## Session Lifecycle

- `POST /v1/auth/login` validates the user password, creates a new session family, and returns an access/refresh token pair.
- `POST /v1/auth/refresh` rotates the refresh session by revoking the current row and inserting a replacement row in the same session family.
- Reusing a revoked refresh token revokes the entire token family and returns `409 Conflict`.
- `POST /v1/auth/logout` revokes the current access token's session.
- `POST /v1/auth/logout-all` revokes every session that belongs to the authenticated user.

## API Key Management

- `GET /v1/organizations/:organization_id/api-keys` lists the active API keys for organization managers.
- `POST /v1/organizations/:organization_id/api-keys` creates a new API key and reveals the generated secret exactly once in the create response.
- `DELETE /v1/organizations/:organization_id/api-keys/:api_key_id` revokes an active API key.
- API key creation participates in the same idempotency model as the other protected write endpoints.

## Machine Authentication

- Machine clients authenticate with `X-API-Key`.
- The server resolves the presented secret through the stored API key prefix and secret hash, then attaches the API key organization to request context.
- The first machine-authenticated slice grants organization-scoped read access to `GET /v1/organizations/:organization_id` and `GET /v1/organizations/:organization_id/memberships` when the path organization matches the API key organization.
- Revoked or expired API keys fail authentication with `401 Unauthorized`.

## Crypto Choices

- Passwords are hashed with `Crypto::Bcrypt::Password` and combined with `PASSWORD_PEPPER` before hashing.
- JWTs are signed with the shared `JWT_SECRET`.
- Refresh token fingerprints use SHA-256 because lookup speed matters and the token itself is already high-entropy and signed.

## Operational Notes

- `JWT_ACCESS_TTL_MINUTES` controls access token lifetime.
- `JWT_REFRESH_TTL_DAYS` controls refresh session expiry.
- `BCRYPT_COST` can be lowered in test environments to keep the suite fast.
- `POST /v1/auth/login` and `POST /v1/auth/refresh` now use a Redis-backed fixed-window throttle before minting tokens.
- Login is keyed by normalized email plus client IP when available. Refresh is keyed by actor id plus client IP when available.
- `AUTH_LOGIN_THROTTLE_LIMIT`, `AUTH_REFRESH_THROTTLE_LIMIT`, and `AUTH_THROTTLE_WINDOW_SECONDS` control the default limiter behavior.
- Setting a throttle limit to `0` disables throttling for that endpoint.
- Throttle rejections use `429 Too Many Requests` with the standard error envelope and `RATE_LIMITED` code.
- Temporary Redis errors fail open so authentication availability does not depend on throttle storage, while `/ready` still reports Redis health separately.
