module KemalcrStarter
  module Modules
    module ApiKeys
      module ApiKeyRoutes
        extend self

        struct CreateApiKeyRequest
          include JSON::Serializable

          getter name : String
        end

        def draw : Nil
          get "/v1/organizations/:organization_id/api-keys" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            page = Core::Http::PageParams.from_env(env)
            total = KemalcrStarter::App.api_key_service.count_for_organization(organization_id)
            items = KemalcrStarter::App.api_key_service.list_for_actor(actor_id, organization_id, limit: page.per_page, offset: page.offset)
            total_pages = (total.to_f / page.per_page).ceil.to_i

            env.response.status_code = 200
            env.response.content_type = "application/json"
            {
              data:       items,
              pagination: {
                page:        page.page,
                per_page:    page.per_page,
                total:       total,
                total_pages: total_pages,
              },
            }.to_json
          end

          post "/v1/organizations/:organization_id/api-keys" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            raw_body = read_request_body(env)
            request = parse_json_body(raw_body, CreateApiKeyRequest)
            raise Core::Errors::ValidationError.new if request.name.strip.empty?

            result = KemalcrStarter::App.idempotency_service.execute(
              idempotency_key(env),
              "POST",
              "/v1/organizations/:organization_id/api-keys",
              actor_id,
              raw_body
            ) do
              api_key = KemalcrStarter::App.api_key_service.create_for_actor(actor_id, organization_id, request.name)
              Core::Idempotency::Response.new(status_code: 201, body: api_key.to_json)
            end

            env.response.status_code = result.status_code
            env.response.content_type = "application/json"
            result.body
          end

          delete "/v1/organizations/:organization_id/api-keys/:api_key_id" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            api_key_id = env.params.url["api_key_id"]

            KemalcrStarter::App.api_key_service.revoke_for_actor(actor_id, organization_id, api_key_id)

            env.response.status_code = 204
            ""
          end
        end

        private def authenticated_actor_id(env : HTTP::Server::Context) : String
          request_context = KemalcrStarter::App.request_context(env)
          raise Core::Errors::UnauthorizedError.new if request_context.actor_id.nil?

          request_context.actor_id.not_nil!
        end

        private def idempotency_key(env : HTTP::Server::Context) : String?
          env.request.headers["Idempotency-Key"]?
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
      end
    end
  end
end
