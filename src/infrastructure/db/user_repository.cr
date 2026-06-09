module KemalcrStarter
  module Infrastructure
    module DB
      record UserRecord,
        id : String,
        email : String,
        name : String,
        status : String

      record UserCredentialsRecord,
        id : String,
        email : String,
        name : String,
        password_digest : String,
        status : String

      class UserRepository < Repository
        def create(id : String, email : String, name : String, password_digest : String, status : String = "active") : UserRecord
          normalized_email = normalize_email(email)

          exec(
            <<-SQL,
              INSERT INTO users (id, email, name, password_digest, status)
              VALUES ($1, $2, $3, $4, $5)
            SQL
            id,
            normalized_email,
            name,
            password_digest,
            status
          )

          find(id).not_nil!
        end

        def find(id : String) : UserRecord?
          one?(
            <<-SQL,
              SELECT id, email, name, status
              FROM users
              WHERE id = $1
            SQL
            id
          ) do |rs|
            UserRecord.new(
              id: rs.read(String),
              email: rs.read(String),
              name: rs.read(String),
              status: rs.read(String)
            )
          end
        end

        def find_credentials_by_email(email : String) : UserCredentialsRecord?
          one?(
            <<-SQL,
              SELECT id, email, name, password_digest, status
              FROM users
              WHERE email = $1
            SQL
            normalize_email(email)
          ) do |rs|
            UserCredentialsRecord.new(
              id: rs.read(String),
              email: rs.read(String),
              name: rs.read(String),
              password_digest: rs.read(String),
              status: rs.read(String)
            )
          end
        end

        def find_credentials(id : String) : UserCredentialsRecord?
          one?(
            <<-SQL,
              SELECT id, email, name, password_digest, status
              FROM users
              WHERE id = $1
            SQL
            id
          ) do |rs|
            UserCredentialsRecord.new(
              id: rs.read(String),
              email: rs.read(String),
              name: rs.read(String),
              password_digest: rs.read(String),
              status: rs.read(String)
            )
          end
        end

        def touch_last_login(id : String, at : Time) : Nil
          exec(
            <<-SQL,
              UPDATE users
              SET last_login_at = $2,
                  updated_at = $2
              WHERE id = $1
            SQL
            id,
            at
          )
        end

        def delete_all : Nil
          exec "DELETE FROM users"
        end

        private def normalize_email(email : String) : String
          email.strip.downcase
        end
      end
    end
  end
end
