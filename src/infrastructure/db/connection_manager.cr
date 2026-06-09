require "db"
require "pg"

module KemalcrStarter
  module Infrastructure
    module DB
      module ConnectionManager
        @@database : ::DB::Database?
        @@database_url : String?

        def self.client(database_url : String) : ::DB::Database
          if database = @@database
            return database if @@database_url == database_url

            database.close
          end

          @@database_url = database_url
          @@database = ::DB.open(database_url)
        end

        def self.ready?(database_url : String) : Bool
          client(database_url).query_one("SELECT 1", as: Int32) == 1
        rescue
          false
        end

        def self.close : Nil
          @@database.try(&.close)
          @@database = nil
          @@database_url = nil
        end
      end
    end
  end
end
