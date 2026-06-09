module KemalcrStarter
  module Core
    module Security
      class CorsHandler < Kemal::Handler
        ALLOWED_METHODS = "GET, POST, PATCH, DELETE, OPTIONS"
        ALLOWED_HEADERS = "Content-Type, Authorization, Idempotency-Key, X-API-Key, X-Request-Id"
        MAX_AGE         = "86400"

        def call(env)
          origin = env.request.headers["Origin"]?
          if origin
            env.response.headers["Access-Control-Allow-Origin"] = allowed_origin(origin)
            env.response.headers["Access-Control-Allow-Methods"] = ALLOWED_METHODS
            env.response.headers["Access-Control-Allow-Headers"] = ALLOWED_HEADERS
            env.response.headers["Access-Control-Allow-Credentials"] = "true"
            env.response.headers["Access-Control-Max-Age"] = MAX_AGE
            env.response.headers["Vary"] = "Origin"
          end

          if env.request.method == "OPTIONS"
            env.response.status_code = 204
          else
            call_next(env)
          end
        end

        private def allowed_origin(origin : String) : String
          configured = ENV["CORS_ORIGINS"]? || "*"
          return origin if configured == "*"

          configured.split(",").each do |allowed|
            return origin if allowed.strip == origin.strip
          end

          configured.split(",").first.strip
        end
      end
    end
  end
end
