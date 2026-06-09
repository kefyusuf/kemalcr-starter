module KemalcrStarter
  module Modules
    module Identity
      module MeRoutes
        extend self

        struct ActiveOrganizationRequest
          include JSON::Serializable

          @[JSON::Field(key: "organization_id")]
          getter organization_id : String
        end

        def draw : Nil
          get "/v1/me" do |env|
            request_context = KemalcrStarter::App.request_context(env)
            raise Core::Errors::UnauthorizedError.new if request_context.actor_id.nil?

            env.response.status_code = 200
            env.response.content_type = "application/json"
            KemalcrStarter::App.me_service.response_for(request_context.actor_id.not_nil!, request_context.organization_id).to_json
          end

          post "/v1/me/active-organization" do |env|
            request_context = KemalcrStarter::App.request_context(env)
            raise Core::Errors::UnauthorizedError.new if request_context.actor_id.nil?

            request = parse_json_body(env, ActiveOrganizationRequest)
            raise Core::Errors::ValidationError.new if request.organization_id.strip.empty?

            response = KemalcrStarter::App.auth_service.switch_active_organization(
              extract_bearer_token(env),
              request.organization_id,
              user_agent(env),
              ip_address(env)
            )

            env.response.status_code = 200
            env.response.content_type = "application/json"
            response.to_json
          end
        end

        private def parse_json_body(env : HTTP::Server::Context, type : T.class) : T forall T
          body = env.request.body.try(&.gets_to_end)
          raise Core::Errors::ValidationError.new("Request body is required.") if body.nil? || body.blank?

          T.from_json(body)
        rescue JSON::ParseException | JSON::SerializableError
          raise Core::Errors::ValidationError.new
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
