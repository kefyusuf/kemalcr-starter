module KemalcrStarter
  module Infrastructure
    module DB
      record OutboxEventRecord,
        id : String,
        aggregate_type : String,
        aggregate_id : String,
        event_type : String,
        event_data : String,
        organization_id : String?,
        correlation_id : String?,
        causation_id : String?,
        status : String,
        attempts : Int32,
        max_retries : Int32,
        last_error : String?,
        locked_at : Time?,
        polled_at : Time?,
        created_at : Time,
        updated_at : Time

      class OutboxEventRepository < Repository
        def create(event : Core::Events::DomainEvent) : Nil
          exec <<-SQL, event.event_id, event.aggregate_type, event.aggregate_id, event.event_type, event.event_data.to_json, event.correlation_id, event.causation_id, event.organization_id
            INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, event_data,
              correlation_id, causation_id, organization_id)
            VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8)
          SQL
        end

        def create(event : Core::Events::DomainEvent, connection : ::DB::Connection) : Nil
          connection.exec <<-SQL, event.event_id, event.aggregate_type, event.aggregate_id, event.event_type, event.event_data.to_json, event.correlation_id, event.causation_id, event.organization_id
            INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, event_data,
              correlation_id, causation_id, organization_id)
            VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8)
          SQL
        end

        def next_batch(batch_size : Int32 = 50) : Array(OutboxEventRecord)
          rows = many(
            <<-SQL,
              SELECT id::text, aggregate_type, aggregate_id, event_type, event_data::text, organization_id,
                correlation_id::text, causation_id::text, status, attempts, max_retries,
                last_error, locked_at, polled_at, created_at, updated_at
              FROM outbox_events
              WHERE status = 'pending'
                AND (locked_at IS NULL OR locked_at < NOW())
              ORDER BY created_at ASC
              LIMIT $1
              FOR UPDATE SKIP LOCKED
            SQL
            batch_size
          ) do |rs|
            OutboxEventRecord.new(
              id: rs.read(String),
              aggregate_type: rs.read(String),
              aggregate_id: rs.read(String),
              event_type: rs.read(String),
              event_data: rs.read(String),
              organization_id: rs.read(String?),
              correlation_id: rs.read(String?),
              causation_id: rs.read(String?),
              status: rs.read(String),
              attempts: rs.read(Int32),
              max_retries: rs.read(Int32),
              last_error: rs.read(String?),
              locked_at: rs.read(Time?),
              polled_at: rs.read(Time?),
              created_at: rs.read(Time),
              updated_at: rs.read(Time)
            )
          end

          unless rows.empty?
            rows.each do |r|
              exec "UPDATE outbox_events SET status = 'in_progress', locked_at = NOW(), polled_at = NOW() WHERE id = $1", r.id
            end
          end

          rows
        end

        def mark_dispatched(event_id : String) : Nil
          exec "UPDATE outbox_events SET status = 'dispatched', locked_at = NULL WHERE id = $1", event_id
        end

        def mark_dispatched(event_id : String, connection : ::DB::Connection) : Nil
          connection.exec "UPDATE outbox_events SET status = 'dispatched', locked_at = NULL WHERE id = $1", event_id
        end

        def increment_retry(event_id : String, error_message : String?, backoff_seconds : Int32 = 0) : Nil
          exec "UPDATE outbox_events SET status = 'pending', attempts = attempts + 1, last_error = $2, locked_at = NOW() + $3::int * INTERVAL '1 second', updated_at = NOW() WHERE id = $1", event_id, error_message, backoff_seconds
        end

        def move_to_dead_letter(event_id : String, failure_reason : String?) : Nil
          database.transaction do |txn|
            conn = txn.connection
            record = conn.query_one?("SELECT id::text, aggregate_type, aggregate_id, event_type, event_data::text, organization_id, correlation_id::text, causation_id::text, status, attempts, max_retries, last_error, locked_at, polled_at, created_at, updated_at FROM outbox_events WHERE id = $1", event_id) do |rs|
              OutboxEventRecord.new(
                id: rs.read(String),
                aggregate_type: rs.read(String),
                aggregate_id: rs.read(String),
                event_type: rs.read(String),
                event_data: rs.read(String),
                organization_id: rs.read(String?),
                correlation_id: rs.read(String?),
                causation_id: rs.read(String?),
                status: rs.read(String),
                attempts: rs.read(Int32),
                max_retries: rs.read(Int32),
                last_error: rs.read(String?),
                locked_at: rs.read(Time?),
                polled_at: rs.read(Time?),
                created_at: rs.read(Time),
                updated_at: rs.read(Time)
              )
            end
            if record
              conn.exec <<-SQL, event_id, record.event_type, record.event_data, record.aggregate_type, record.aggregate_id, record.correlation_id, record.causation_id, failure_reason, record.attempts, record.organization_id
                INSERT INTO dead_letter_events (original_event_id, event_type, event_data, aggregate_type, aggregate_id, correlation_id, causation_id, failure_reason, retry_count, organization_id)
                VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7, $8, $9, $10)
              SQL
              conn.exec "UPDATE outbox_events SET status = 'dead_letter', locked_at = NULL, updated_at = NOW() WHERE id = $1", event_id
            end
          end
        end

        def mark_dead(event_id : String, error_message : String?) : Nil
          exec "UPDATE outbox_events SET status = 'dead_letter', last_error = $2, locked_at = NULL, updated_at = NOW() WHERE id = $1", event_id, error_message
        end

        def mark_dead(event_id : String, error_message : String?, connection : ::DB::Connection) : Nil
          connection.exec "UPDATE outbox_events SET status = 'dead_letter', last_error = $2, locked_at = NULL, updated_at = NOW() WHERE id = $1", event_id, error_message
        end

        def reclaim_stale_in_progress(stale_threshold_seconds : Int32 = 30) : Int32
          result = exec "UPDATE outbox_events SET status = 'pending', locked_at = NULL WHERE status = 'in_progress' AND locked_at < NOW() - $1::int * INTERVAL '1 second'", stale_threshold_seconds
          result.rows_affected.to_i
        end

        def find(id : String) : OutboxEventRecord?
          one? "SELECT id::text, aggregate_type, aggregate_id, event_type, event_data::text, organization_id, correlation_id::text, causation_id::text, status, attempts, max_retries, last_error, locked_at, polled_at, created_at, updated_at FROM outbox_events WHERE id = $1", id do |rs|
            OutboxEventRecord.new(
              id: rs.read(String),
              aggregate_type: rs.read(String),
              aggregate_id: rs.read(String),
              event_type: rs.read(String),
              event_data: rs.read(String),
              organization_id: rs.read(String?),
              correlation_id: rs.read(String?),
              causation_id: rs.read(String?),
              status: rs.read(String),
              attempts: rs.read(Int32),
              max_retries: rs.read(Int32),
              last_error: rs.read(String?),
              locked_at: rs.read(Time?),
              polled_at: rs.read(Time?),
              created_at: rs.read(Time),
              updated_at: rs.read(Time)
            )
          end
        end

        record DeadLetterRecord,
          id : String,
          original_event_id : String?,
          event_type : String,
          event_data : String,
          organization_id : String?,
          aggregate_type : String,
          aggregate_id : String,
          correlation_id : String?,
          causation_id : String?,
          failure_reason : String?,
          retry_count : Int32,
          failed_at : Time

        def list_dead_letters : Array(DeadLetterRecord)
          many(
            <<-SQL
              SELECT id, original_event_id, event_type, event_data::text, organization_id, aggregate_type, aggregate_id,
                correlation_id, causation_id, failure_reason, retry_count, failed_at
              FROM dead_letter_events
              ORDER BY failed_at DESC
            SQL
          ) do |rs|
            DeadLetterRecord.new(
              id: rs.read(String),
              original_event_id: rs.read(String?),
              event_type: rs.read(String),
              event_data: rs.read(String),
              organization_id: rs.read(String?),
              aggregate_type: rs.read(String),
              aggregate_id: rs.read(String),
              correlation_id: rs.read(String?),
              causation_id: rs.read(String?),
              failure_reason: rs.read(String?),
              retry_count: rs.read(Int32),
              failed_at: rs.read(Time)
            )
          end
        end

        def requeue_dead_letter(dead_letter_id : String) : Bool
          result = false
          database.transaction do |txn|
            conn = txn.connection
            dl = conn.query_one?("SELECT id, original_event_id, event_type, event_data::text, organization_id, aggregate_type, aggregate_id, correlation_id, causation_id FROM dead_letter_events WHERE id = $1", dead_letter_id) do |rs|
              DeadLetterRecord.new(
                id: rs.read(String),
                original_event_id: rs.read(String?),
                event_type: rs.read(String),
                event_data: rs.read(String),
                organization_id: rs.read(String?),
                aggregate_type: rs.read(String),
                aggregate_id: rs.read(String),
                correlation_id: rs.read(String?),
                causation_id: rs.read(String?),
                failure_reason: nil,
                retry_count: 0,
                failed_at: Time.utc
              )
            end

            if dl
              conn.exec "INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, event_data, correlation_id, causation_id, organization_id) VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8)",
                dl.id, dl.aggregate_type, dl.aggregate_id, dl.event_type, dl.event_data, dl.correlation_id, dl.causation_id, dl.organization_id
              conn.exec "DELETE FROM dead_letter_events WHERE id = $1", dead_letter_id
              result = true
            end
          end
          result
        end
      end
    end
  end
end
