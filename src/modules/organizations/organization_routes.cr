module KemalcrStarter
  module Modules
    module Organizations
      module OrganizationRoutes
        extend self

        struct CreateOrganizationRequest
          include JSON::Serializable

          getter slug : String
          getter name : String
        end

        struct UpdateOrganizationRequest
          include JSON::Serializable

          getter slug : String?
          getter name : String?
        end

        struct CreateInvitationRequest
          include JSON::Serializable

          getter email : String
          getter role : String
        end

        def draw : Nil
          get "/v1/organizations" do |env|
            actor_id = authenticated_actor_id(env)
            page = Core::Http::PageParams.from_env(env)
            total = KemalcrStarter::App.organization_service.count_for_actor(actor_id)
            items = KemalcrStarter::App.organization_service.list_for_actor(actor_id, limit: page.per_page, offset: page.offset)
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

          post "/v1/organizations" do |env|
            actor_id = authenticated_actor_id(env)
            raw_body = read_request_body(env)
            request = parse_json_body(raw_body, CreateOrganizationRequest)
            raise Core::Errors::ValidationError.new if request.slug.strip.empty? || request.name.strip.empty?

            result = KemalcrStarter::App.idempotency_service.execute(
              idempotency_key(env),
              "POST",
              "/v1/organizations",
              actor_id,
              raw_body
            ) do
              organization = KemalcrStarter::App.organization_service.create_for_actor(actor_id, request.slug, request.name)
              Core::Idempotency::Response.new(status_code: 201, body: organization.to_json)
            end

            env.response.status_code = result.status_code
            env.response.content_type = "application/json"
            result.body
          end

          get "/v1/organizations/:organization_id" do |env|
            request_context = KemalcrStarter::App.request_context(env)
            organization_id = env.params.url["organization_id"]

            env.response.status_code = 200
            env.response.content_type = "application/json"
            KemalcrStarter::App.organization_service.get_for_request(
              request_context.actor_id,
              request_context.organization_id,
              organization_id
            ).to_json
          end

          get "/v1/organizations/:organization_id/memberships" do |env|
            request_context = KemalcrStarter::App.request_context(env)
            organization_id = env.params.url["organization_id"]
            page = Core::Http::PageParams.from_env(env)
            total = KemalcrStarter::App.organization_service.count_memberships(organization_id)
            items = KemalcrStarter::App.organization_service.list_memberships_for_request(
              request_context.actor_id,
              request_context.organization_id,
              organization_id,
              limit: page.per_page,
              offset: page.offset
            )
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

          get "/v1/organizations/:organization_id/invitations" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            page = Core::Http::PageParams.from_env(env)
            total = KemalcrStarter::App.organization_service.count_invitations(organization_id)
            items = KemalcrStarter::App.organization_service.list_invitations_for_actor(actor_id, organization_id, limit: page.per_page, offset: page.offset)
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

          post "/v1/organizations/:organization_id/invitations" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            raw_body = read_request_body(env)
            request = parse_json_body(raw_body, CreateInvitationRequest)

            result = KemalcrStarter::App.idempotency_service.execute(
              idempotency_key(env),
              "POST",
              "/v1/organizations/:organization_id/invitations",
              actor_id,
              raw_body
            ) do
              invitation = KemalcrStarter::App.organization_service.invite_user_for_actor(
                actor_id,
                organization_id,
                request.email,
                request.role
              )

              Core::Idempotency::Response.new(status_code: 201, body: invitation.to_json)
            end

            env.response.status_code = result.status_code
            env.response.content_type = "application/json"
            result.body
          end

          post "/v1/organizations/:organization_id/invitations/:invitation_id/accept" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            invitation_id = env.params.url["invitation_id"]

            membership = KemalcrStarter::App.organization_service.accept_invitation_for_actor(
              actor_id,
              organization_id,
              invitation_id
            )

            env.response.status_code = 200
            env.response.content_type = "application/json"
            membership.to_json
          end

          delete "/v1/organizations/:organization_id/invitations/:invitation_id" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            invitation_id = env.params.url["invitation_id"]

            KemalcrStarter::App.organization_service.revoke_invitation_for_actor(
              actor_id,
              organization_id,
              invitation_id
            )

            env.response.status_code = 204
            ""
          end

          patch "/v1/organizations/:organization_id" do |env|
            actor_id = authenticated_actor_id(env)
            organization_id = env.params.url["organization_id"]
            request = parse_json_body(env, UpdateOrganizationRequest)

            organization = KemalcrStarter::App.organization_service.update_for_actor(
              actor_id,
              organization_id,
              request.slug,
              request.name
            )

            env.response.status_code = 200
            env.response.content_type = "application/json"
            organization.to_json
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

        private def parse_json_body(env : HTTP::Server::Context, type : T.class) : T forall T
          parse_json_body(read_request_body(env), type)
        end
      end
    end
  end
end
