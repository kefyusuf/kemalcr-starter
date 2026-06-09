module KemalcrStarter
  module Core
    module Tenancy
      class AuthenticationHandler < Kemal::Handler
        def initialize(@auth_service : Modules::Identity::AuthService, @api_key_service : Modules::ApiKeys::ApiKeyService)
        end

        def call(env)
          if bearer_token = extract_bearer_token(env)
            claims = @auth_service.authenticate_access_token(bearer_token)
            request_context = env.get("request_context").as(Http::RequestContext)

            env.set(
              "request_context",
              Http::RequestContext.new(
                request_id: request_context.request_id,
                actor_id: claims.user_id,
                organization_id: claims.active_organization_id,
                session_id: claims.session_id,
                api_key_id: nil
              )
            )
          elsif api_key = extract_api_key(env)
            claims = @api_key_service.authenticate(api_key)
            request_context = env.get("request_context").as(Http::RequestContext)

            env.set(
              "request_context",
              Http::RequestContext.new(
                request_id: request_context.request_id,
                actor_id: nil,
                organization_id: claims.organization_id,
                session_id: nil,
                api_key_id: claims.api_key_id
              )
            )
          end

          call_next(env)
        end

        private def extract_bearer_token(env : HTTP::Server::Context) : String?
          header = env.request.headers["Authorization"]?
          return nil if header.nil?

          scheme, token = header.split(' ', 2)
          raise Core::Errors::UnauthorizedError.new unless scheme == "Bearer"
          raise Core::Errors::UnauthorizedError.new if token.nil? || token.blank?

          token
        end

        private def extract_api_key(env : HTTP::Server::Context) : String?
          secret = env.request.headers["X-API-Key"]?
          return nil if secret.nil? || secret.blank?

          secret
        end
      end
    end
  end
end
