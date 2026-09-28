module KemalcrStarter
  module Modules
    module Webhooks
      module WebhookRoutes
        extend self

        struct CreateEndpointRequest
          include JSON::Serializable

          getter url : String
          getter description : String?
          @[JSON::Field(key: "event_types")]
          getter event_types : Array(String)
        end

        def draw : Nil
          post "/v1/organizations/:organization_id/webhooks" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            request = parse_json_body(env, CreateEndpointRequest)
            created = KemalcrStarter::App.webhook_service.create_endpoint(
              actor_id,
              organization_id,
              request.url,
              request.description,
              request.event_types
            )

            env.response.status_code = 201
            env.response.content_type = "application/json"
            {
              id:              created.endpoint.id,
              organization_id: created.endpoint.organization_id,
              url:             created.endpoint.url,
              description:     created.endpoint.description,
              event_types:     created.endpoint.event_types,
              active:          created.endpoint.active,
              created_at:      created.endpoint.created_at,
              secret:          created.secret,
            }.to_json
          end

          get "/v1/organizations/:organization_id/webhooks" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            endpoints = KemalcrStarter::App.webhook_service.list_endpoints(actor_id, organization_id)

            env.response.status_code = 200
            env.response.content_type = "application/json"
            {
              webhooks:   endpoints.map { |e| {id: e.id, url: e.url, description: e.description, event_types: e.event_types, active: e.active, created_at: e.created_at} },
              count:      endpoints.size,
              request_id: KemalcrStarter::App.request_context(env).request_id,
            }.to_json
          end

          get "/v1/organizations/:organization_id/webhooks/:webhook_id/deliveries" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            webhook_id = env.params.url["webhook_id"]
            deliveries = KemalcrStarter::App.webhook_service.list_deliveries(actor_id, organization_id, webhook_id)

            env.response.status_code = 200
            env.response.content_type = "application/json"
            {
              deliveries: deliveries.map { |d|
                {
                  id:              d.id,
                  event_id:        d.event_id,
                  event_type:      d.event_type,
                  status:          d.status,
                  attempt_count:   d.attempt_count,
                  response_status: d.response_status,
                  last_error:      d.last_error,
                  delivered_at:    d.delivered_at.try(&.to_rfc3339),
                  created_at:      d.created_at.to_rfc3339,
                }
              },
              count:      deliveries.size,
              request_id: KemalcrStarter::App.request_context(env).request_id,
            }.to_json
          end

          delete "/v1/organizations/:organization_id/webhooks/:webhook_id" do |env|
            actor_id = KemalcrStarter::App.request_context(env).actor_id
            raise Core::Errors::UnauthorizedError.new unless actor_id

            organization_id = env.params.url["organization_id"]
            webhook_id = env.params.url["webhook_id"]
            revoked = KemalcrStarter::App.webhook_service.revoke_endpoint(actor_id, organization_id, webhook_id)

            if revoked
              env.status(200).json({status: "revoked", request_id: KemalcrStarter::App.request_context(env).request_id})
            else
              env.status(404).json({status: "not_found", request_id: KemalcrStarter::App.request_context(env).request_id})
            end
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
      end
    end
  end
end
