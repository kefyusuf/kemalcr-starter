module KemalcrStarter
  module Infrastructure
    module DB
      record IdempotencyKeyRecord,
        id : String,
        scope : String,
        idempotency_key : String,
        request_fingerprint : String,
        response_status : Int32?,
        response_body_ref : String?,
        locked_until : Time?

      class IdempotencyKeyRepository < Repository
        def create(id : String, scope : String, idempotency_key : String, request_fingerprint : String, locked_until : Time) : IdempotencyKeyRecord
          exec(
            <<-SQL,
              INSERT INTO idempotency_keys (
                id,
                scope,
                idempotency_key,
                request_fingerprint,
                locked_until
              )
              VALUES ($1, $2, $3, $4, $5)
            SQL
            id,
            scope,
            idempotency_key,
            request_fingerprint,
            locked_until
          )

          find(scope, idempotency_key).not_nil!
        end

        def find(scope : String, idempotency_key : String) : IdempotencyKeyRecord?
          one?(
            <<-SQL,
              SELECT id, scope, idempotency_key, request_fingerprint, response_status, response_body_ref, locked_until
              FROM idempotency_keys
              WHERE scope = $1
                AND idempotency_key = $2
            SQL
            scope,
            idempotency_key
          ) do |rs|
            map_record(rs)
          end
        end

        def complete(id : String, response_status : Int32, response_body : String) : IdempotencyKeyRecord?
          exec(
            <<-SQL,
              UPDATE idempotency_keys
              SET response_status = $2,
                  response_body_ref = $3,
                  locked_until = NULL
              WHERE id = $1
            SQL
            id,
            response_status,
            response_body
          )

          find_by_id(id)
        end

        def delete(id : String) : Nil
          exec(
            <<-SQL,
              DELETE FROM idempotency_keys
              WHERE id = $1
            SQL
            id
          )
        end

        private def find_by_id(id : String) : IdempotencyKeyRecord?
          one?(
            <<-SQL,
              SELECT id, scope, idempotency_key, request_fingerprint, response_status, response_body_ref, locked_until
              FROM idempotency_keys
              WHERE id = $1
            SQL
            id
          ) do |rs|
            map_record(rs)
          end
        end

        private def map_record(rs : ::DB::ResultSet) : IdempotencyKeyRecord
          IdempotencyKeyRecord.new(
            id: rs.read(String),
            scope: rs.read(String),
            idempotency_key: rs.read(String),
            request_fingerprint: rs.read(String),
            response_status: rs.read(Int32?),
            response_body_ref: rs.read(String?),
            locked_until: rs.read(Time?)
          )
        end
      end
    end
  end
end
