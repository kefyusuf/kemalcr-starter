CREATE TABLE IF NOT EXISTS outbox_events (
    id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id VARCHAR(100) NOT NULL,
    event_type VARCHAR(200) NOT NULL,
    event_data JSONB NOT NULL,
    correlation_id VARCHAR(36),
    causation_id VARCHAR(36),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'in_progress', 'dispatched', 'dead_letter')),
    attempts INT NOT NULL DEFAULT 0,
    max_retries INT NOT NULL DEFAULT 5,
    last_error TEXT,
    locked_at TIMESTAMPTZ,
    polled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_outbox_events_pending
    ON outbox_events (created_at)
    WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS dead_letter_events (
    id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    original_event_id VARCHAR(36),
    event_type VARCHAR(200) NOT NULL,
    event_data JSONB NOT NULL,
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id VARCHAR(100) NOT NULL,
    correlation_id VARCHAR(36),
    causation_id VARCHAR(36),
    failure_reason TEXT,
    retry_count INT NOT NULL DEFAULT 0,
    failed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
