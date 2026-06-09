module KemalcrStarter
  module Infrastructure
    module DB
      abstract class Repository
        def initialize(@database : ::DB::Database | ::DB::Connection)
        end

        protected getter database : ::DB::Database | ::DB::Connection

        protected def exec(sql : String, *args)
          database.exec(sql, *args)
        end

        protected def one?(sql : String, *args, &block : ::DB::ResultSet -> T) : T? forall T
          database.query_one?(sql, *args) do |rs|
            yield rs
          end
        end

        protected def many(sql : String, *args, &block : ::DB::ResultSet -> T) : Array(T) forall T
          database.query_all(sql, *args) do |rs|
            yield rs
          end
        end

        protected def transaction(&block : ::DB::Connection -> T) : T forall T
          database.transaction do |txn|
            yield txn.connection
          end
        end
      end
    end
  end
end
