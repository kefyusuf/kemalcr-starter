require "redis"
require "uri"

module KemalcrStarter
  module Infrastructure
    module Redis
      module ClientManager
        @@client : ::Redis::Client?
        @@redis_url : String?

        def self.client(redis_url : String) : ::Redis::Client
          if client = @@client
            return client if @@redis_url == redis_url
          end

          @@redis_url = redis_url
          @@client = ::Redis::Client.new(URI.parse(redis_url))
        end

        def self.ready?(redis_url : String) : Bool
          client(redis_url).ping == "PONG"
        rescue
          false
        end

        def self.namespaced_key(namespace : String, *parts : String) : String
          ([namespace] + parts.to_a).join(":")
        end
      end
    end
  end
end
