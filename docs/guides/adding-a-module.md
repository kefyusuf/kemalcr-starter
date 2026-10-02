# Adding a Module (Plug-and-Play Template)

This guide uses `products` as the reference module. Copy this shape for new domains.

## 1. Schema

Add a migration pair under `db/migrations/`:

- `NNN_create_<table>.up.sql` / `.down.sql`
- Scope rows with `organization_id` when the resource is tenant-owned
- Add uniqueness / lookup indexes up front

## 2. Repository

`src/infrastructure/db/<name>_repository.cr`

- Inherit `Infrastructure::DB::Repository`
- Define a `record` for the row type
- Parameterized SQL only (`$1`, `$2`, …)
- Keep mapping in a private `map_*` helper

## 3. Events

`src/modules/<name>/events.cr`

- Subclass `Core::Events::DomainEvent`
- Use dotted event types: `product.created`, `product.updated`, `product.deleted`
- Put tenant-scoped fields in `event_data` JSON

## 4. Service

`src/modules/<name>/product_service.cr` (or `<name>_service.cr`)

- Constructor: `settings`, `database`, optional `OutboxEventRepository`
- Call `@rbac_service.authorize!` at the start of each use case
- Publish domain events inside the business transaction path
- Return view records, not raw DB rows

## 5. Routes

`src/modules/<name>/<name>_routes.cr`

- `extend self`, a `draw : Nil` method that registers Kemal routes
- Namespace under `/v1/organizations/:organization_id/...`
- Resolve `actor_id` from `App.request_context(env)`
- Parse JSON with local request structs

## 6. Permissions

Extend `Core::Rbac::Permission` (and `to_s` / `from_s`):

- Example: `ProductManage`, `ProductList`
- Owner inherits all permissions automatically
- Put read-only permissions into `MEMBER_PERMISSIONS` if members need them

## 7. Wiring

In `src/kemalcr_starter.cr`:

1. `require` repository, events, service, routes
2. Lazy singleton: `App.product_service`
3. Draw routes only when enabled:

```crystal
if Core::Plugins::ModuleRegistry.enabled?(settings, "products")
  Modules::Products::ProductRoutes.draw
end
```

4. Add `"products"` to `Core::Plugins::ModuleRegistry.known_pluggable`
5. Default `ENABLED_MODULES` in Settings + `.env.example`

## 8. Tests

- Unit/service spec with a seeded org + actor (`spec/products_spec.cr`)
- Extend `TestDatabase.truncate_all!` with the new table(s)
- Cover RBAC denial as well as the happy path

## Optional: fan-out

Read [outbox claims and recovery](outbox-claims-and-recovery.md) for worker ownership and replay limits. Handlers must tolerate redelivery.

Register a handler for your events (or `*` for all) via `HandlerRegistry`.
Webhooks already subscribe to `*`, so new domain events are delivered automatically.
