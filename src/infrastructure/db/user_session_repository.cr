module KemalcrStarter
  module Infrastructure
    module DB
      record UserSessionRecord,
        id : String,
        user_id : String,
        session_family_id : String,
        refresh_token_hash : String,
        expires_at : Time,
        revoked_at : Time?,
        rotated_from_id : String?

      class UserSessionRepository < Repository
        def create(
          id : String,
          user_id : String,
          session_family_id : String,
          refresh_token_hash : String,
          expires_at : Time,
          user_agent : String? = nil,
          ip_address : String? = nil,
          rotated_from_id : String? = nil,
        ) : UserSessionRecord
          exec(
            <<-SQL,
              INSERT INTO user_sessions (
                id,
                user_id,
                session_family_id,
                refresh_token_hash,
                user_agent,
                ip_address,
                expires_at,
                rotated_from_id
              )
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            SQL
            id,
            user_id,
            session_family_id,
            refresh_token_hash,
            user_agent,
            ip_address,
            expires_at,
            rotated_from_id
          )

          find(id).not_nil!
        end

        def find(id : String) : UserSessionRecord?
          one?(
            <<-SQL,
              SELECT id, user_id, session_family_id, refresh_token_hash, expires_at, revoked_at, rotated_from_id
              FROM user_sessions
              WHERE id = $1
            SQL
            id
          ) do |rs|
            map_session(rs)
          end
        end

        def active?(id : String, user_id : String, now : Time = Time.utc) : Bool
          one?(
            <<-SQL,
              SELECT 1
              FROM user_sessions
              WHERE id = $1
                AND user_id = $2
                AND revoked_at IS NULL
                AND expires_at > $3
            SQL
            id,
            user_id,
            now
          ) do |_rs|
            true
          end || false
        end

        def revoke(id : String, revoked_at : Time) : Nil
          exec(
            <<-SQL,
              UPDATE user_sessions
              SET revoked_at = COALESCE(revoked_at, $2)
              WHERE id = $1
            SQL
            id,
            revoked_at
          )
        end

        def revoke_family(session_family_id : String, revoked_at : Time) : Nil
          exec(
            <<-SQL,
              UPDATE user_sessions
              SET revoked_at = COALESCE(revoked_at, $2)
              WHERE session_family_id = $1
            SQL
            session_family_id,
            revoked_at
          )
        end

        def revoke_all_for_user(user_id : String, revoked_at : Time) : Nil
          exec(
            <<-SQL,
              UPDATE user_sessions
              SET revoked_at = COALESCE(revoked_at, $2)
              WHERE user_id = $1
            SQL
            user_id,
            revoked_at
          )
        end

        def delete_all : Nil
          exec "DELETE FROM user_sessions"
        end

        private def map_session(rs : ::DB::ResultSet) : UserSessionRecord
          UserSessionRecord.new(
            id: rs.read(String),
            user_id: rs.read(String),
            session_family_id: rs.read(String),
            refresh_token_hash: rs.read(String),
            expires_at: rs.read(Time),
            revoked_at: rs.read(Time?),
            rotated_from_id: rs.read(String?)
          )
        end
      end
    end
  end
end
