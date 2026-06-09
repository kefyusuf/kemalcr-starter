module KemalcrStarter
  module Core
    module Errors
      class ErrorHandler < Kemal::Handler
        def call(env)
          call_next(env)
        rescue ex : ApiError
          write_error(env, ex.status_code, ex.code, ex.message || ex.code, ex.details)
        rescue ex
          log_context = Logging::RequestLogContext.from_env(env)

          Log.error do
            "Unhandled exception request_id=#{log_context.request_id} method=#{log_context.method} path=#{log_context.path} error=#{ex.class.name}"
          end

          write_error(env, 500, "INTERNAL_SERVER_ERROR", "An internal server error occurred.")
        end

        private def write_error(env : HTTP::Server::Context, status_code : Int32, code : String, message : String, details : Hash(String, String) = Hash(String, String).new) : Nil
          request_id = env.get?("request_context").try(&.as(Core::Http::RequestContext)).try(&.request_id) || Core::Http::RequestContextHandler.generate_request_id

          env.response.status_code = status_code
          env.response.content_type = "application/json"
          env.response.headers[Core::Http::RequestContextHandler::REQUEST_ID_HEADER] = request_id
          env.response.print(
            {
              error: {
                code:       code,
                message:    message,
                details:    details,
                request_id: request_id,
              },
            }.to_json
          )
        end
      end
    end
  end
end
