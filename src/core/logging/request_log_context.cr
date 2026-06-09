module KemalcrStarter
  module Core
    module Logging
      record RequestLogContext,
        request_id : String,
        method : String,
        path : String,
        actor_id : String? = nil,
        organization_id : String? = nil do
        def self.from_env(env : HTTP::Server::Context) : RequestLogContext
          request_context = env.get?("request_context").try(&.as(Http::RequestContext))

          new(
            request_id: request_context.try(&.request_id) || "unknown",
            method: env.request.method,
            path: env.request.path,
            actor_id: request_context.try(&.actor_id),
            organization_id: request_context.try(&.organization_id)
          )
        end
      end
    end
  end
end
