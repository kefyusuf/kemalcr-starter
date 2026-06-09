module KemalcrStarter
  module Core
    module Security
      class SecurityHeadersHandler < Kemal::Handler
        def call(env)
          env.response.headers["X-Content-Type-Options"] = "nosniff"
          env.response.headers["X-Frame-Options"] = "DENY"
          env.response.headers["Referrer-Policy"] = "same-origin"

          call_next(env)
        end
      end
    end
  end
end
