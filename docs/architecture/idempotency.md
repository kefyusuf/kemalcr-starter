# Idempotency Architecture

The first idempotency slice is intentionally narrow and currently protects `POST /v1/organizations`, `POST /v1/organizations/:organization_id/invitations`, `POST /v1/auth/refresh`, and `POST /v1/organizations/:organization_id/api-keys`.

## Request Identity

- Idempotent requests are activated only when the `Idempotency-Key` header is present.
- The request scope is derived from the authenticated actor, the HTTP method, and the route scope.
- For `POST /v1/auth/refresh`, actor identity is derived from the refresh token claims before the business operation runs.
- The request fingerprint is a SHA-256 digest of method, route scope, actor identity, and the normalized JSON body.

## Runtime Behavior

- The first request acquires a short Redis lock before the write operation starts.
- A matching completed request replays the original HTTP status and response body.
- Reusing the same key with a different payload returns `409 Conflict`.
- A duplicate request that arrives while the first request is still incomplete also returns `409 Conflict`.

## Persistence Model

- Redis is used only for the short-lived in-flight lock.
- PostgreSQL stores the durable idempotency audit row in `idempotency_keys`.
- The first implementation stores the replayable response body directly in `response_body_ref` to keep replay logic simple.

## Failure Policy

- If Redis cannot provide the lock, the request fails closed with `409 Conflict` and no write is attempted.
- If the protected business operation fails, the unfinished idempotency row is deleted so the caller can retry with the same key.
