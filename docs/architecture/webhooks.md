# Webhook tenant isolation

Outbound webhook endpoints belong to an organization. Subscription filters select event types inside that organization; an empty filter means all of its tenant-owned events. Authentication or an event-type filter alone is not a tenant boundary.

## Event ownership

`Core::Events::DomainEvent#organization_id` is the ownership contract. Organization events use their organization aggregate ID. Product, membership, API-key and checkout events expose their explicit organization ID. Identity events and billing events without a resolved organization remain global/unscoped and are not delivered to tenant webhooks.

Ownership is stored in nullable `organization_id` columns on `outbox_events` and `dead_letter_events`, preserved during retry/requeue, and restored by the publisher. Endpoint queries require both this organization ID and a matching event type. Dispatch returns without creating a delivery or making an HTTP request when ownership is missing or blank. It does not infer ownership from `event_data`, aggregate identifiers or the current request context.

Custom modules can pass `organization_id:` to the event base constructor or expose a typed `organization_id` getter. Their producer must resolve ownership from authorized business state. JSON webhook envelopes include a top-level `organization_id`; existing payload fields stay available. HMAC signs the complete serialized body, including the new field.

## Upgrade and rollback

Run migration `015_add_event_organization_id` before starting the updated application. It adds nullable metadata columns without changing existing payloads. Old application writes remain possible during schema expansion, but old application instances still have the previous delivery behavior; drain/replace all old publishers before resuming outbound delivery in an affected deployment.

Pre-upgrade outbox/dead-letter rows have null ownership and therefore cannot produce external webhook deliveries with the updated publisher. Internal handlers still receive those events. Do not automatically backfill tenant identity from arbitrary payloads. If historical external delivery is needed, use a separately reviewed mapping from trusted business records and verify the destination organization first.

The down migration removes ownership metadata. Use it only with an application version that does not require these columns. Rolling back the application restores the earlier webhook behavior; a safer rollback for an affected environment is to stop/disable outbound webhooks and retain the additive schema while investigating. No automatic legacy data replay or backfill is provided.

## Guarantees and remaining work

Integration specs exercise actual PostgreSQL persistence, publisher reconstruction, local HTTP receivers, filtered/wildcard subscriptions, global and unscoped events, retries and dead-letter requeue across two organizations. Existing HMAC and delivery-status behavior is retained.

This change establishes the tenant routing boundary. Operational endpoint authorization, production SSRF/egress protection, transaction-bound business writes, atomic publisher claims and per-handler idempotency are separate readiness work packages. Do not interpret this fix as completion of all production gates.
