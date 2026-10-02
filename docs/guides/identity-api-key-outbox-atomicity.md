# Identity and API-key outbox atomicity

Existing identity and API-key event producers commit domain writes and pending events through the same PostgreSQL transaction connection.

| Operation | Transaction contents |
|---|---|
| Registration | User, first session, `identity.user.created` |
| Login | New session, login timestamps, `identity.user.logged_in` |
| Logout | Session revocation, `identity.session.revoked` |
| Logout all | User session revocations, `identity.user.logged_out` |
| Confirm password reset | Password, reset-token consumption/invalidation, session revocations, `identity.user.password_reset` |
| Create API key | Key, `api_key.created` |
| Revoke API key | Revocation, `api_key.revoked` |

Mutation repositories use `txn.connection`, and outbox insertion uses `create(event, connection: txn.connection)`. If either write fails, PostgreSQL rolls back the complete operation. Tokens and API secrets are returned only after a successful commit. Existing event payloads and aggregate conventions are retained, including the user aggregate ID and session_id payload on `identity.session.revoked`. Credentials are not added to event data.

## Upgrade and operations

No migration or new configuration is required. AuthService, PasswordResetService and ApiKeyService now default to a database outbox repository when omitted or nil. Such callers need the outbox schema and can no longer suppress events by omitting that dependency. App explicitly injects the API-key outbox repository; previously its nil wiring omitted these events.

An outbox failure now fails the operation and preserves the previous security state. In particular, failed logout/revoke leaves the session/key active, and failed password reset retains the previous password and usable reset tokens. Clients must treat a failed response as unsuccessful and retry after recovery. Application rollback restores the previous non-atomic behavior. No backfill of previously missing events is included.

## Limits and validation

This change covers existing event producers. Refresh and organization switching retain their existing transactions without new events. Password-reset request email delivery remains synchronous and outside this guarantee. Concurrent token consumption/session rotation/revocation and permission changes need separate policies; precondition reads are not locked by this change. Password-reset user-status behavior and optional RBAC requirements are unchanged.

Atomic persistence does not guarantee exactly-once delivery. Publisher claims, replay handling and crash-safe idempotency remain separate work. Other producer PRs must be integrated and verified together before promotion.

Integration tests reject real PostgreSQL inserts and check domain rollback, session/key usability, credential confidentiality, reset token reuse, default repositories and App API-key wiring. Existing request, rotation, reset and idempotency suites validate the retained contracts.
