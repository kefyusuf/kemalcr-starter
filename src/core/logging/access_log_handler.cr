module KemalcrStarter
  module Core
    module Logging
      class AccessLogHandler < Kemal::Handler
        def call(env)
          start = Time.monotonic
          call_next(env)
          duration_ms = (Time.monotonic - start).total_milliseconds

          ctx = RequestLogContext.from_env(env)
          Log.info do
            String.build do |io|
              io << "method=" << ctx.method
              io << " path=" << ctx.path
              io << " status=" << env.response.status_code
              io << " duration_ms=" << duration_ms.round(2)
              io << " request_id=" << ctx.request_id
              io << " actor_id=" << (ctx.actor_id || "-")
              io << " org_id=" << (ctx.organization_id || "-")
            end
          end
        end
      end
    end
  end
end
