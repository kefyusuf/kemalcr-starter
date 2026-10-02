module KemalcrStarter
  module Infrastructure
    module DB
      class ProcessedEventRepository < Repository
        def consume_once(event_id : String, handler_name : String, &block : ::DB::Connection -> Nil) : Bool
          consumed = false
          database.transaction do |txn|
            connection = txn.connection
            inserted = connection.exec <<-SQL, event_id, handler_name
              INSERT INTO processed_events (event_id, handler_name) VALUES ($1, $2)
              ON CONFLICT (event_id, handler_name) DO NOTHING
            SQL
            if inserted.rows_affected == 1
              yield connection
              consumed = true
            end
          end
          consumed
        end

        def already_processed?(event_id : String, handler_name : String) : Bool
          existing = one? "SELECT 1 FROM processed_events WHERE event_id = $1 AND handler_name = $2", event_id, handler_name do |rs|
            rs.read(Int32)
          end
          !existing.nil?
        end

        def mark_processed(event_id : String, handler_name : String) : Nil
          exec "INSERT INTO processed_events (event_id, handler_name) VALUES ($1, $2) ON CONFLICT DO NOTHING", event_id, handler_name
        end
      end
    end
  end
end
