# Organization and membership outbox atomicity

OrganizationService commits each organization or invitation mutation and its pending event through the same PostgreSQL transaction connection. If either write fails, both roll back.

| Operation | Transaction contents |
|---|---|
| Create organization | Organization, owner membership, `organization.created` |
| Update organization | Updated fields, `organization.updated` |
| Invite user | Pending membership, `organization.membership.invited` |
| Accept invitation | Active membership and joined timestamp, `organization.membership.accepted` |
| Revoke invitation | Revoked membership, `organization.membership.revoked` |

Repository objects used for mutations and readback are constructed with `txn.connection`. Outbox insertion uses `OutboxEventRepository#create(event, connection: txn.connection)`. A pool-backed repository can acquire another connection, so using a transaction block alone does not make its writes atomic.

Authorization checks, normalization, event payloads and response shapes retain their existing semantics. Missing, nonpending and unauthorized invitations are rejected before writing an event. Revocation also checks that its mutation returned a record before inserting the event.

## Upgrade

No migration or new configuration is required. Production composition already injects the outbox repository. Callers that omit it or pass nil now use a default database outbox repository and require the outbox schema to be available. Repository injection does not opt out of event persistence.

Apply migrations before starting the application as usual. Deploy the application through the existing release gates. Rolling back the application restores the previous non-atomic behavior. No data repair for previously missing events is included.

## Verification and limits

Integration tests reject actual PostgreSQL outbox inserts with a CHECK constraint and verify rollback for all five operations, including owner membership, timestamps and joined_at. Tests also cover default event persistence, matching aggregate IDs and payloads, duplicate writes, invalid input and access denials. Existing request and idempotency tests cover the HTTP contract.

This guarantee covers OrganizationService producers. Identity and API-key producers, publisher claims and consumer replay remain separate work. Atomic persistence does not promise exactly-once delivery.

Concurrent acceptance/revocation and membership permission changes still need a separate state-transition policy. Precondition reads remain outside the mutation transaction; no row lock or conditional pending-state update is introduced here. Existing broad DB-error mapping and optional RBAC dependency behavior are unchanged.
