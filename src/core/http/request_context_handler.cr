require "uuid"

module KemalcrStarter
  module Core
    module Http
      class RequestContextHandler < Kemal::Handler
        REQUEST_ID_HEADER = "X-Request-Id"

        def initialize(@settings : Config::Settings)
        end

        def call(env)
          request_id = env.request.headers[REQUEST_ID_HEADER]? || self.class.generate_request_id
          request_context = RequestContext.new(request_id: request_id)

          env.set "request_context", request_context
          env.response.headers[REQUEST_ID_HEADER] = request_id
          env.response.headers["X-App-Environment"] = @settings.environment

          call_next(env)
        end

        def self.generate_request_id : String
          "req_#{UUID.random}"
        end
      end
    end
  end
end
