module KemalcrStarter
  module Modules
    module Identity
      module AuthRoutes
        extend self

        struct RegisterRequest
          include JSON::Serializable

          getter name : String
          getter email : String
          getter password : String
        end

        struct LoginRequest
          include JSON::Serializable

          getter email : String
          getter password : String
        end

        struct RefreshRequest
          include JSON::Serializable

          @[JSON::Field(key: "refresh_token")]
          getter refresh_token : String
        end

        struct LogoutResponse
          include JSON::Serializable

          getter status : String

          def initialize(@status : String = "ok")
          end
        end

        def draw : Nil
          post "/v1/auth/register" do |env|
            request = parse_json_body(env, RegisterRequest)
            validate_register_request!(request)
            KemalcrStarter::App.auth_throttle.check!(
              AuthThrottleContext.new(
                endpoint: "/v1/auth/register",
                actor_id: nil,
                email: normalized_email_str(request.email),
                ip_address: ip_address(env),
                user_agent: user_agent(env)
              )
            )
            response = KemalcrStarter::App.auth_service.register(request.name, request.email, request.password, user_agent(env), ip_address(env))

            env.response.status_code = 201
            env.response.content_type = "application/json"
            response.to_json
          end

          post "/v1/auth/login" do |env|
            request = parse_json_body(env, LoginRequest)
            validate_login_request!(request)
            KemalcrStarter::App.auth_throttle.check!(
              AuthThrottleContext.new(
                endpoint: "/v1/auth/login",
                actor_id: nil,
                email: normalized_email(request),
                ip_address: ip_address(env),
                user_agent: user_agent(env)
              )
            )
            response = KemalcrStarter::App.auth_service.login(request.email, request.password, user_agent(env), ip_address(env))

            env.response.status_code = 200
            env.response.content_type = "application/json"
            response.to_json
          end

          post "/v1/auth/refresh" do |env|
            raw_body = read_request_body(env)
            request = parse_json_body(raw_body, RefreshRequest)
            validate_refresh_request!(request)

            actor_id = refresh_actor_id(request.refresh_token)
            KemalcrStarter::App.auth_throttle.check!(
              AuthThrottleContext.new(
                endpoint: "/v1/auth/refresh",
                actor_id: actor_id,
                email: nil,
                ip_address: ip_address(env),
                user_agent: user_agent(env)
              )
            )
            result = KemalcrStarter::App.idempotency_service.execute(
              idempotency_key(env),
              "POST",
              "/v1/auth/refresh",
              actor_id,
              raw_body
            ) do
              response = KemalcrStarter::App.auth_service.refresh(request.refresh_token, user_agent(env), ip_address(env))
              Core::Idempotency::Response.new(status_code: 200, body: response.to_json)
            end

            env.response.status_code = result.status_code
            env.response.content_type = "application/json"
            result.body
          end

          post "/v1/auth/logout" do |env|
            KemalcrStarter::App.auth_service.logout(extract_bearer_token(env))

            env.response.status_code = 200
            env.response.content_type = "application/json"
            LogoutResponse.new.to_json
          end

          post "/v1/auth/logout-all" do |env|
            KemalcrStarter::App.auth_service.logout_all(extract_bearer_token(env))

            env.response.status_code = 200
            env.response.content_type = "application/json"
            LogoutResponse.new.to_json
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

        private def validate_register_request!(request : RegisterRequest) : Nil
          raise Core::Errors::ValidationError.new if request.name.strip.empty?
          raise Core::Errors::ValidationError.new if request.email.strip.empty?
        end

        private def validate_login_request!(request : LoginRequest) : Nil
          if request.email.strip.empty? || request.password.empty?
            raise Core::Errors::ValidationError.new
          end
        end

        private def normalized_email_str(email : String) : String
          email.strip.downcase
        end

        private def validate_refresh_request!(request : RefreshRequest) : Nil
          raise Core::Errors::ValidationError.new if request.refresh_token.strip.empty?
        end

        private def normalized_email(request : LoginRequest) : String
          request.email.strip.downcase
        end

        private def refresh_actor_id(refresh_token : String) : String
          KemalcrStarter::App.auth_service.decode_refresh_actor_id(refresh_token)
        end

        private def idempotency_key(env : HTTP::Server::Context) : String?
          env.request.headers["Idempotency-Key"]?
        end

        private def extract_bearer_token(env : HTTP::Server::Context) : String
          header = env.request.headers["Authorization"]?
          raise Core::Errors::UnauthorizedError.new if header.nil?

          scheme, token = header.split(' ', 2)
          raise Core::Errors::UnauthorizedError.new unless scheme == "Bearer"
          raise Core::Errors::UnauthorizedError.new if token.nil? || token.blank?

          token
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
