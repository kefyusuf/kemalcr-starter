ALTER TABLE outbox_events ADD COLUMN organization_id TEXT;
ALTER TABLE dead_letter_events ADD COLUMN organization_id TEXT;
