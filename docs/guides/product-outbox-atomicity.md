# Product mutation and outbox atomicity

`ProductService` commits each product create, update or delete together with its corresponding outbox event in one PostgreSQL transaction. If the product mutation or event insertion fails, neither change commits. The pending event can be seen by the publisher only after commit.

The service binds the write repository and its readback to `txn.connection`, then calls `OutboxEventRepository#create(event, connection: txn.connection)`. Using a database-backed repository inside the block would open another pool connection and defeat this guarantee.

The optional constructor argument controls dependency injection, not event emission. Omitting it or supplying nil creates the default outbox repository on the service database. Callers can no longer silently skip events through a missing repository. Existing production composition already injects that repository. Low-level repository calls remain available for infrastructure work; they do not themselves emit domain events.

Successful mutations preserve the existing event types and payloads: `product.created`, `product.updated` and `product.deleted`. Missing or foreign-organization products preserve their existing nil/false outcomes and generate no event. Authorization and normalization rules remain in place.

## Extend the pattern

```crystal
record = database.transaction do |txn|
  repository = ProductRepository.new(txn.connection)
  created = repository.create(...)
  outbox.create(ProductCreated.new(...), connection: txn.connection)
  created
end.not_nil!
```

Keep all reads needed for the mutation on the same bound repository. Write the durable event before leaving the transaction block. Do not swallow an outbox error and return success. External delivery belongs to the publisher after commit.

## Verification and upgrade

Integration specs use a real PostgreSQL CHECK constraint to reject outbox insertion and verify that creation, all updated fields/timestamp and deletion roll back. Positive cases check committed product identity, normalized payloads and pending event status. Duplicate-SKU, missing-product and foreign-organization cases verify that no orphan or unauthorized events are emitted. Test constraints are removed after each example and run only in the isolated test database.

No database migration or new configuration is needed. Existing installations still require the normal schema migrations, including the outbox table. Repository-less service callers now write events and surface outbox errors, so ensure the publisher and failure monitoring are configured. Rolling back the application restores the old non-atomic behavior; already committed events remain pending according to existing publisher rules.

This guarantee covers ProductService CRUD only. Organization, API-key and identity producers still need their own transaction work. It does not provide exactly-once external delivery, atomic publisher claims, consumer deduplication, crash-safe idempotency or serializable concurrent PATCH behavior. Those remain separate R2 work packages.
