module KemalcrStarter
  module Infrastructure
    module DB
      record PasswordResetTokenRecord,
        id : String,
        user_id : String,
        token_hash : String,
        expires_at : Time,
        used_at : Time?,
        created_at : Time

      class PasswordResetTokenRepository < Repository
        def create(id : String, user_id : String, token_hash : String, expires_at : Time) : PasswordResetTokenRecord
          now = Time.utc
          exec(
            "INSERT INTO password_reset_tokens (id, user_id, token_hash, expires_at, created_at) VALUES ($1, $2, $3, $4, $5)",
            id, user_id, token_hash, expires_at, now
          )
          PasswordResetTokenRecord.new(id, user_id, token_hash, expires_at, nil, now)
        end

        def find_active_by_hash(token_hash : String) : PasswordResetTokenRecord?
          one?(
            "SELECT id, user_id, token_hash, expires_at, used_at, created_at FROM password_reset_tokens WHERE token_hash = $1 AND used_at IS NULL AND expires_at > NOW()",
            token_hash
          ) do |rs|
            PasswordResetTokenRecord.new(
              rs.read(String),
              rs.read(String),
              rs.read(String),
              rs.read(Time),
              rs.read(Time?),
              rs.read(Time)
            )
          end
        end

        def mark_used!(id : String) : Nil
          exec("UPDATE password_reset_tokens SET used_at = NOW() WHERE id = $1", id)
        end

        def invalidate_active_for_user(user_id : String) : Nil
          exec("UPDATE password_reset_tokens SET used_at = NOW() WHERE user_id = $1 AND used_at IS NULL", user_id)
        end

        def delete_expired! : Nil
          exec("DELETE FROM password_reset_tokens WHERE expires_at < NOW() - INTERVAL '1 day'")
        end
      end
    end
  end
end
