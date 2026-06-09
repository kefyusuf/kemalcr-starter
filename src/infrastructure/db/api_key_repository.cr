module KemalcrStarter
  module Infrastructure
    module DB
      record ApiKeyRecord,
        id : String,
        organization_id : String,
        name : String,
        key_prefix : String,
        secret_hash : String,
        last_used_at : Time?,
        revoked_at : Time?,
        expires_at : Time?,
        created_at : Time

      class ApiKeyRepository < Repository
        def create(id : String, organization_id : String, name : String, key_prefix : String, secret_hash : String, expires_at : Time? = nil) : ApiKeyRecord
          exec(
            <<-SQL,
              INSERT INTO api_keys (
                id,
                organization_id,
                name,
                key_prefix,
                secret_hash,
                expires_at
              )
              VALUES ($1, $2, $3, $4, $5, $6)
            SQL
            id,
            organization_id,
            name,
            key_prefix,
            secret_hash,
            expires_at
          )

          find(id).not_nil!
        end

        def find(id : String) : ApiKeyRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, name, key_prefix, secret_hash, last_used_at, revoked_at, expires_at, created_at
              FROM api_keys
              WHERE id = $1
            SQL
            id
          ) do |rs|
            map_api_key(rs)
          end
        end

        def find_active_by_prefix(key_prefix : String) : ApiKeyRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, name, key_prefix, secret_hash, last_used_at, revoked_at, expires_at, created_at
              FROM api_keys
              WHERE key_prefix = $1
                AND revoked_at IS NULL
                AND (expires_at IS NULL OR expires_at > NOW())
              ORDER BY created_at DESC
              LIMIT 1
            SQL
            key_prefix
          ) do |rs|
            map_api_key(rs)
          end
        end

        def count_active_for_organization(organization_id : String) : Int64
          one?(
            <<-SQL,
              SELECT COUNT(*)::bigint
              FROM api_keys
              WHERE organization_id = $1
                AND revoked_at IS NULL
                AND (expires_at IS NULL OR expires_at > NOW())
            SQL
            organization_id
          ) do |rs|
            rs.read(Int64)
          end || 0_i64
        end

        def list_active_for_organization(organization_id : String, limit : Int32 = 1000, offset : Int32 = 0) : Array(ApiKeyRecord)
          many(
            <<-SQL,
              SELECT id, organization_id, name, key_prefix, secret_hash, last_used_at, revoked_at, expires_at, created_at
              FROM api_keys
              WHERE organization_id = $1
                AND revoked_at IS NULL
                AND (expires_at IS NULL OR expires_at > NOW())
              ORDER BY created_at ASC
              LIMIT $2 OFFSET $3
            SQL
            organization_id,
            limit,
            offset
          ) do |rs|
            map_api_key(rs)
          end
        end

        def find_active_for_organization(id : String, organization_id : String) : ApiKeyRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, name, key_prefix, secret_hash, last_used_at, revoked_at, expires_at, created_at
              FROM api_keys
              WHERE id = $1
                AND organization_id = $2
                AND revoked_at IS NULL
                AND (expires_at IS NULL OR expires_at > NOW())
            SQL
            id,
            organization_id
          ) do |rs|
            map_api_key(rs)
          end
        end

        def revoke(id : String, at : Time) : ApiKeyRecord?
          exec(
            <<-SQL,
              UPDATE api_keys
              SET revoked_at = $2
              WHERE id = $1
                AND revoked_at IS NULL
            SQL
            id,
            at
          )

          find(id)
        end

        def touch_last_used(id : String, at : Time) : ApiKeyRecord?
          exec(
            <<-SQL,
              UPDATE api_keys
              SET last_used_at = $2
              WHERE id = $1
            SQL
            id,
            at
          )

          find(id)
        end

        def delete_all : Nil
          exec "DELETE FROM api_keys"
        end

        private def map_api_key(rs : ::DB::ResultSet) : ApiKeyRecord
          ApiKeyRecord.new(
            id: rs.read(String),
            organization_id: rs.read(String),
            name: rs.read(String),
            key_prefix: rs.read(String),
            secret_hash: rs.read(String),
            last_used_at: rs.read(Time?),
            revoked_at: rs.read(Time?),
            expires_at: rs.read(Time?),
            created_at: rs.read(Time)
          )
        end
      end
    end
  end
end
