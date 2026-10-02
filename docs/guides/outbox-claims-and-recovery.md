# Outbox claims and recovery

The publisher claims due pending events and changes their state to `in_progress` in one PostgreSQL statement. Candidate selection uses `FOR UPDATE SKIP LOCKED`, a batch limit and deterministic `created_at, id` ordering. Returned records contain the committed claim state. A failed batch update rolls back every claim in that statement.

## Claim identity

`locked_at` remains the lease start or retry deadline. `polled_at` also identifies each claim: PostgreSQL advances it to the greater of the current clock and the previous stamp plus one microsecond. It must never be cleared or reset between claims. This preserves distinct identities even inside an outer transaction or when the wall clock moves backward. Read timestamps through the repository; avoid truncating or reconstructing them in worker code.

Publisher completion, retry and dead-letter operations accept the claimed OutboxEventRecord and require both `in_progress` status and matching `polled_at`. A reclaimed, retried or completed claim cannot write its old result. Stats count successful state transitions. Dead-letter insertion and its state transition are atomic; a failed insertion leaves the claim recoverable.

Existing repository methods accepting only an event ID remain for compatibility and administrative callers. They do not fence ownership and must not be used to finish publisher claims. Operator requeue and older application versions are separate integration concerns.

## Recovery and limits

The publisher retains the existing 30-second stale-claim threshold. Reclaim changes abandoned `in_progress` rows to pending and clears their lease; retry history and the prior identity remain. Pending backoff deadlines and fresh claims are preserved. Reclaimed events can be redelivered.

No heartbeat or external side-effect fencing is introduced. A slow handler or a large serial batch can outlive the threshold and run again; consumers need replay-safe behavior. Ownership guards protect database state but cannot undo external effects already performed. This remains at-least-once delivery, not exactly-once. Lease renewal, consumer deduplication and shutdown are separate work.

## Upgrade and verification

No migration or new configuration is required. Stop every old publisher before starting this version: old workers use unconditional completion/retry writes and can bypass ownership guards. Do not operate mixed publisher versions. Preserve polled_at when repairing or requeueing existing outbox rows; newly inserted rows can begin without a stamp. Rolling back restores unsafe claim behavior.

Tests use real PostgreSQL queries with a test-only scheduling barrier between query return and caller continuation. This forces a second poll into the old selection/update window. Additional tests cover rejected batch rollback, updated snapshots, monotonic identity, stale recovery/backoff and stale publisher outcomes. Existing publisher retry and repository suites cover ordinary dispatch.
