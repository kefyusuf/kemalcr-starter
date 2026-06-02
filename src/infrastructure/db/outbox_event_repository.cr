require "./events"

module KemalcrStarter
  module Infrastructure
    module DB
      class OutboxEventRecord
        include DB::Serializable

        getter id : String
        getter aggregate_type : String
        getter aggregate_id : String
        getter event_type : String
        getter event_data : String
        getter correlation_id : String?
        getter causation_id : String?
        getter status : String
        getter attempts : Int32
        getter max_retries : Int32
        getter last_error : String?
        getter locked_at : Time?
        getter polled_at : Time?
        getter created_at : Time
        getter updated_at : Time
      end

      class OutboxEventRepository < Repository
        def create(event : Core::Events::DomainEvent) : Nil
          exec <<-SQL, event.event_id, event.aggregate_type, event.aggregate_id, event.event_type,
            event.event_data.to_json, event.correlation_id, event.causation_id
            INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, event_data,
              correlation_id, causation_id)
            VALUES ($1, $2, $3, $4, $5::jsonb, $6::uuid, $7::uuid)
          SQL
        end

        def create(event : Core::Events::DomainEvent, connection : ::DB::Connection) : Nil
          connection.exec <<-SQL, event.event_id, event.aggregate_type, event.aggregate_id, event.event_type,
            event.event_data.to_json, event.correlation_id, event.causation_id
            INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, event_data,
              correlation_id, causation_id)
            VALUES ($1, $2, $3, $4, $5::jsonb, $6::uuid, $7::uuid)
          SQL
        end

        def next_batch(batch_size : Int32 = 50) : Array(OutboxEventRecord)
          rows = many <<-SQL, batch_size
            SELECT * FROM outbox_events
            WHERE status = 'pending'
              AND (locked_at IS NULL OR locked_at < NOW())
            ORDER BY created_at ASC
            LIMIT $1
            FOR UPDATE SKIP LOCKED
          SQL

          unless rows.empty?
            ids = rows.map(&.id)
            placeholders = ids.map_with_index { |_, i| "$#{i + 1}" }.join(", ")
            exec "UPDATE outbox_events SET status = 'in_progress', locked_at = NOW(), polled_at = NOW() WHERE id IN (#{placeholders})", ids
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
          exec "UPDATE outbox_events SET attempts = attempts + 1, last_error = $2, locked_at = NOW() + $3::int * INTERVAL '1 second', updated_at = NOW() WHERE id = $1", event_id, error_message, backoff_seconds
        end

        def move_to_dead_letter(event_id : String, failure_reason : String?) : Nil
          transaction do |txn|
            conn = txn.connection
            row = one?("SELECT * FROM outbox_events WHERE id = $1", event_id)
            if row
              conn.exec <<-SQL, event_id, row.event_type, row.event_data, row.aggregate_type, row.aggregate_id, row.correlation_id, row.causation_id, failure_reason, row.attempts
                INSERT INTO dead_letter_events (original_event_id, event_type, event_data, aggregate_type,
                  aggregate_id, correlation_id, causation_id, failure_reason, retry_count)
                VALUES ($1, $2, $3::jsonb, $4, $5, $6::uuid, $7::uuid, $8, $9)
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
          result.rows_affected
        end

        def find(id : String) : OutboxEventRecord?
          one? "SELECT * FROM outbox_events WHERE id = $1", id
        end
      end
    end
  end
end
