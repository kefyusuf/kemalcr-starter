module KemalcrStarter
  module Infrastructure
    module DB
      class Migrator
        MIGRATIONS_TABLE = "schema_migrations"

        def initialize(@settings : Core::Config::Settings)
        end

        def run(action : String) : Nil
          case action
          when "up"
            up
          when "down"
            down
          when "reset"
            reset
          when "status"
            status
          else
            raise ArgumentError.new("Unsupported migration action: #{action}")
          end
        end

        def up : Nil
          ensure_migrations_table
          applied = applied_versions.to_set

          up_files.each do |file|
            version = version_from(file, ".up.sql")
            next if applied.includes?(version)

            database.transaction do |txn|
              connection = txn.connection
              execute_sql_file(connection, file)
              connection.exec "INSERT INTO #{MIGRATIONS_TABLE} (version) VALUES ($1)", version
            end
          end
        end

        def down : Nil
          ensure_migrations_table
          version = latest_version
          return unless version

          file = File.join(@settings.migrations_path, "#{version}.down.sql")
          raise "Missing down migration for #{version}" unless File.exists?(file)

          database.transaction do |txn|
            connection = txn.connection
            execute_sql_file(connection, file)
            connection.exec "DELETE FROM #{MIGRATIONS_TABLE} WHERE version = $1", version
          end
        end

        def reset : Nil
          ensure_migrations_table

          while latest_version
            down
          end

          up
        end

        def status : Nil
          ensure_migrations_table
          puts "Applied migrations:"
          applied_versions.each { |version| puts "- #{version}" }
        end

        private def database : ::DB::Database
          ConnectionManager.client(@settings.database_url)
        end

        private def ensure_migrations_table : Nil
          database.exec <<-SQL
            CREATE TABLE IF NOT EXISTS #{MIGRATIONS_TABLE} (
              version TEXT PRIMARY KEY,
              applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
          SQL
        end

        private def applied_versions : Array(String)
          database.query_all("SELECT version FROM #{MIGRATIONS_TABLE} ORDER BY version", as: String)
        rescue
          [] of String
        end

        private def latest_version : String?
          database.query_one?("SELECT version FROM #{MIGRATIONS_TABLE} ORDER BY version DESC LIMIT 1", as: String)
        rescue
          nil
        end

        private def up_files : Array(String)
          Dir.glob(File.join(@settings.migrations_path, "*.up.sql")).sort
        end

        private def version_from(file : String, suffix : String) : String
          File.basename(file).rchop(suffix)
        end

        private def execute_sql_file(connection : ::DB::Connection, file : String) : Nil
          statements = File.read(file)
            .split(/;\s*\n/m)
            .map(&.strip)
            .reject(&.empty?)

          statements.each do |statement|
            connection.exec statement
          end
        end
      end
    end
  end
end
