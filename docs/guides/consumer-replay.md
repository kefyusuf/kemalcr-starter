# Durable database consumer replay

ProcessedEventRepository provides `consume_once(event_id, handler_name) { |connection| ... }` for database consumers. It inserts the completion marker and runs the effect through the same transaction connection. The composite `(event_id, handler_name)` key admits one winner; concurrent deliveries wait for that transaction. A committed marker skips later calls. Any callback or commit error rolls back the marker and effect, allowing retry.

Use a stable consumer name and the original event ID. Construct repositories with the supplied connection. Calling a pool-backed repository or external service inside the callback does not make its effect atomic. Existing `already_processed?` / `mark_processed` methods remain for compatibility; checking then marking in separate transactions is not a safe consumer workflow.

## Built-in audit effects

AuditLogRepository uses stable names `audit:<action>`. Repeated deliveries become successful no-ops for the database audit effect. Its existing one-audit-row-per-event constraint is preserved. A matching legacy audit row (event, action, resource type and resource ID) is recognized and marked complete without insertion. A conflicting legacy action/resource remains an error and does not leave a marker.

This protects audit writes made by organization, membership, API-key and user handlers. It does not mean the entire handler executes only once. Membership invitation's simulated email log still runs on replay; future notification delivery needs its own durable consumer design. Existing unsupported event mappings are not changed.

## Upgrade and rollback

Apply migration `016_scope_processed_events_to_consumer` before running the application. It preserves existing marker rows and changes the primary key from event ID to event ID plus handler name. Migration 015 belongs to the independent tenant-ownership PR and must be integrated separately. Stop old consumers during rollout; old marker semantics and unconditional audit insertion can bypass the new workflow.

Down migration preserves data and fails transactionally if multiple consumers have completed the same event, because the old event-only primary key cannot represent those rows. It does not silently delete markers. Prefer retaining the additive schema during application rollback; rollback to old consumer code restores its unsafe behavior. Do not delete markers merely to enable replay. Marker retention must cover the application's replay horizon, including retention of audit rows.

## Limits

The guarantee applies to effects in one PostgreSQL transaction using the original event identity. HTTP delivery and email cannot be rolled back by this mechanism; webhook receivers must deduplicate `X-Webhook-Event-Id`. Dead-letter requeue currently assigns a new event ID, so it is treated as a new event and can create another audit row. Requeue identity and external-effect deduplication remain separate work.

No exactly-once claim is made for the full delivery pipeline. Integrate the producer, ownership and publisher PRs and run their combined suite before promotion.
