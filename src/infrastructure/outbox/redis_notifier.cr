module KemalcrStarter
  module Infrastructure
    module Outbox
      class RedisNotifier
        CHANNEL = "events:new"

        def initialize(@redis_url : String)
        end

        def notify_new_event(event_id : String) : Nil
          spawn do
            begin
              redis = Redis::Client.new(URI.parse(@redis_url))
              redis.publish(CHANNEL, event_id)
              redis.close
            rescue ex
              Log.warn(exception: ex) { "Redis notifier: failed to publish to #{CHANNEL}" }
            end
          end
        rescue ex
          Log.warn(exception: ex) { "Redis notifier: failed to spawn publish fiber" }
        end
      end
    end
  end
end
