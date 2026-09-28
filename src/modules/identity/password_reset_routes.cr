module KemalcrStarter
  module Modules
    module Identity
      module PasswordResetRoutes
        extend self

        struct RequestResetRequest
          include JSON::Serializable

          getter email : String
        end

        struct ConfirmResetRequest
          include JSON::Serializable

          getter token : String
          getter password : String
        end

        struct AcceptedResponse
          include JSON::Serializable

          getter status : String

          def initialize(@status : String = "accepted")
          end
        end

        def draw : Nil
          post "/v1/auth/password-reset/request" do |env|
            request = parse_json_body(env, RequestResetRequest)
            raise Core::Errors::ValidationError.new if request.email.strip.empty?

            KemalcrStarter::App.auth_throttle.check!(
              AuthThrottleContext.new(
                endpoint: "/v1/auth/register",
                actor_id: nil,
                email: request.email.strip.downcase,
                ip_address: ip_address(env),
                user_agent: user_agent(env)
              )
            )

            KemalcrStarter::App.password_reset_service.request_reset(request.email)

            env.response.status_code = 202
            env.response.content_type = "application/json"
            AcceptedResponse.new.to_json
          end

          post "/v1/auth/password-reset/confirm" do |env|
            request = parse_json_body(env, ConfirmResetRequest)
            raise Core::Errors::ValidationError.new if request.token.strip.empty?

            KemalcrStarter::App.password_reset_service.confirm_reset(request.token, request.password)

            env.response.status_code = 200
            env.response.content_type = "application/json"
            AcceptedResponse.new(status: "ok").to_json
          end
        end

        private def read_request_body(env : HTTP::Server::Context) : String
          body = env.request.body.try(&.gets_to_end)
          raise Core::Errors::ValidationError.new("Request body is required.") if body.nil? || body.blank?

          body
        end

        private def parse_json_body(body : String, type : T.class) : T forall T
          T.from_json(body)
        rescue JSON::ParseException | JSON::SerializableError
          raise Core::Errors::ValidationError.new
        end

        private def parse_json_body(env : HTTP::Server::Context, type : T.class) : T forall T
          parse_json_body(read_request_body(env), type)
        end

        private def user_agent(env : HTTP::Server::Context) : String?
          env.request.headers["User-Agent"]?
        end

        private def ip_address(env : HTTP::Server::Context) : String?
          env.request.headers["X-Forwarded-For"]?
        end
      end
    end
  end
end
