module KemalcrStarter
  module Infrastructure
    module DB
      record AuditLogRecord,
        id : String,
        event_id : String,
        actor_id : String?,
        action : String,
        resource_type : String,
        resource_id : String,
        old_value : String?,
        new_value : String?,
        metadata : String?,
        created_at : Time

      class AuditLogRepository < Repository
        def create(
          id : String,
          event_id : String,
          actor_id : String?,
          action : String,
          resource_type : String,
          resource_id : String,
          old_value : String? = nil,
          new_value : String? = nil,
          metadata : String? = nil,
        ) : Nil
          ProcessedEventRepository.new(database).consume_once(event_id, "audit:#{action}") do |connection|
            existing = connection.scalar <<-SQL, event_id, action, resource_type, resource_id
              SELECT EXISTS (
                SELECT 1 FROM audit_logs WHERE event_id = $1 AND action = $2
                  AND resource_type = $3 AND resource_id = $4
              )
            SQL
            unless existing.as(Bool)
              connection.exec <<-SQL, id, event_id, actor_id, action, resource_type, resource_id, old_value, new_value, metadata
                INSERT INTO audit_logs (id, event_id, actor_id, action, resource_type, resource_id, old_value, new_value, metadata)
                VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9::jsonb)
              SQL
            end
          end
        end

        def list(action : String, limit : Int32 = 50, offset : Int32 = 0) : Array(AuditLogRecord)
          many(
            <<-SQL,
              SELECT id, event_id, actor_id, action, resource_type, resource_id,
                old_value::text, new_value::text, metadata::text, created_at
              FROM audit_logs
              ORDER BY created_at DESC
              LIMIT $1 OFFSET $2
            SQL
            limit,
            offset
          ) do |rs|
            AuditLogRecord.new(
              id: rs.read(String),
              event_id: rs.read(String),
              actor_id: rs.read(String?),
              action: rs.read(String),
              resource_type: rs.read(String),
              resource_id: rs.read(String),
              old_value: rs.read(String?),
              new_value: rs.read(String?),
              metadata: rs.read(String?),
              created_at: rs.read(Time)
            )
          end
        end

        def delete_all : Nil
          exec "DELETE FROM audit_logs"
        end
      end
    end
  end
end
