require "digest/sha256"

module KemalcrStarter
  module Modules
    module Identity
      record AuthThrottleContext,
        endpoint : String,
        actor_id : String?,
        email : String?,
        ip_address : String?,
        user_agent : String?

      abstract class AuthThrottle
        abstract def check!(context : AuthThrottleContext) : Nil
      end

      class NoopAuthThrottle < AuthThrottle
        def check!(context : AuthThrottleContext) : Nil
        end
      end

      class RedisAuthThrottle < AuthThrottle
        def initialize(*, redis_url : String, login_limit : Int32, refresh_limit : Int32, register_limit : Int32, window_seconds : Int32)
          @redis = Infrastructure::Redis::ClientManager.client(redis_url)
          @login_limit = login_limit
          @refresh_limit = refresh_limit
          @register_limit = register_limit
          @window_seconds = window_seconds
        end

        def check!(context : AuthThrottleContext) : Nil
          limit = limit_for(context.endpoint)
          return if limit <= 0

          identifier = throttle_identifier(context)
          return if identifier.nil?

          key = throttle_key(context.endpoint, identifier)
          count = @redis.incr(key)
          @redis.expire(key, @window_seconds + 1) if count == 1

          return if count <= limit

          raise Core::Errors::TooManyRequestsError.new(
            details: {
              "endpoint"            => context.endpoint,
              "retry_after_seconds" => @window_seconds.to_s,
            }
          )
        rescue ex : Core::Errors::TooManyRequestsError
          raise ex
        rescue
          # Fail open so temporary Redis issues do not block authentication entirely.
        end

        private def limit_for(endpoint : String) : Int32
          case endpoint
          when "/v1/auth/login"
            @login_limit
          when "/v1/auth/refresh"
            @refresh_limit
          when "/v1/auth/register"
            @register_limit
          else
            0
          end
        end

        private def throttle_identifier(context : AuthThrottleContext) : String?
          case context.endpoint
          when "/v1/auth/login"
            join_identity(context.email, context.ip_address, context.user_agent)
          when "/v1/auth/refresh"
            join_identity(context.actor_id, context.ip_address, context.user_agent)
          when "/v1/auth/register"
            join_identity(context.email, context.ip_address, context.user_agent)
          else
            nil
          end
        end

        private def join_identity(primary : String?, secondary : String?, fallback : String?) : String?
          values = [] of String

          [primary, secondary].each do |value|
            next if value.nil?

            normalized = value.strip
            values << normalized.downcase unless normalized.empty?
          end

          return values.join(":") unless values.empty?

          fallback_value = fallback.try(&.strip)
          return nil if fallback_value.nil? || fallback_value.empty?

          fallback_value.downcase
        end

        private def throttle_key(endpoint : String, identifier : String) : String
          bucket = Time.utc.to_unix // @window_seconds
          Infrastructure::Redis::ClientManager.namespaced_key(
            "auth_throttle",
            Digest::SHA256.hexdigest(endpoint),
            bucket.to_s,
            Digest::SHA256.hexdigest(identifier)
          )
        end
      end
    end
  end
end
