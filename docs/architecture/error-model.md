# Error Model

## Purpose

The API uses a single structured error envelope so clients can handle failures consistently.

## Envelope

```json
{
  "error": {
    "code": "AUTH_UNAUTHORIZED",
    "message": "Authentication failed.",
    "details": {},
    "request_id": "req_01jtxexample"
  }
}
```

## Rules

1. `code` is machine-stable.
2. `message` is human-readable.
3. `details` carries structured context for clients.
4. `request_id` must match the request tracking header.

## Current Error Types

- `AUTH_UNAUTHORIZED`
- `AUTH_FORBIDDEN`
- `REQUEST_CONFLICT`
- `RATE_LIMITED`
- `VALIDATION_ERROR`
- `INTERNAL_SERVER_ERROR`

## HTTP Mapping

- `401` for authentication failures
- `403` for authorization failures
- `409` for idempotency conflicts and refresh token reuse conflicts
- `429` for auth throttling rejections
- `422` for validation failures
- `500` for unhandled internal failures

## Operational Notes

All API responses should carry `X-Request-Id` so logs and client-reported failures can be correlated quickly.

The internal server error response must never leak stack traces or raw exception details to the client.

`details` is used selectively for machine-readable context such as the throttled endpoint or retry window. Clients should treat missing detail keys as normal.
