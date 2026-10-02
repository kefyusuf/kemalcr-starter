require "uuid"
require "random/secure"
require "openssl/hmac"
require "http/client"
require "uri"

module KemalcrStarter
  module Modules
    module Webhooks
      record EndpointView,
        id : String,
        organization_id : String,
        url : String,
        description : String?,
        event_types : Array(String),
        active : Bool,
        created_at : String

      record CreatedEndpoint,
        endpoint : EndpointView,
        secret : String

      class WebhookService
        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database,
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil)
          @endpoint_repository = Infrastructure::DB::WebhookEndpointRepository.new(@database)
          @delivery_repository = Infrastructure::DB::WebhookDeliveryRepository.new(@database)
          @rbac_service = Core::Rbac::AuthorizationService.new(
            Infrastructure::DB::RbacRepository.new(@database)
          )
        end

        def create_endpoint(actor_id : String, organization_id : String, url : String,
                            description : String?, event_types : Array(String)) : CreatedEndpoint
          validate_url!(url)
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::WebhookManage)

          id = "whk_#{UUID.random}"
          secret = Random::Secure.urlsafe_base64(32)
          record = @endpoint_repository.create(
            id: id,
            organization_id: organization_id,
            url: url.strip,
            secret: secret,
            description: description,
            event_types: event_types,
            created_by: actor_id
          )

          CreatedEndpoint.new(endpoint: view(record), secret: secret)
        end

        def list_endpoints(actor_id : String, organization_id : String) : Array(EndpointView)
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::WebhookManage)
          @endpoint_repository.list_for_organization(organization_id).map { |record| view(record) }
        end

        def revoke_endpoint(actor_id : String, organization_id : String, endpoint_id : String) : Bool
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::WebhookManage)
          endpoint = @endpoint_repository.find(endpoint_id)
          return false unless endpoint
          return false unless endpoint.organization_id == organization_id

          @endpoint_repository.revoke(endpoint_id)
        end

        def list_deliveries(actor_id : String, organization_id : String, endpoint_id : String) : Array(Infrastructure::DB::WebhookDeliveryRecord)
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::WebhookManage)
          endpoint = @endpoint_repository.find(endpoint_id)
          return [] of Infrastructure::DB::WebhookDeliveryRecord unless endpoint
          return [] of Infrastructure::DB::WebhookDeliveryRecord unless endpoint.organization_id == organization_id

          @delivery_repository.list_for_endpoint(endpoint_id)
        end

        # Called from the outbox event pipeline. Raises on failure so the publisher retries.
        def dispatch_event(event : Core::Events::DomainEvent) : Nil
          organization_id = event.organization_id
          return if organization_id.nil? || organization_id.blank?

          endpoints = @endpoint_repository.list_active_for_event_type(organization_id, event.event_type)
          return if endpoints.empty?

          payload = event.to_json
          failures = [] of String

          endpoints.each do |endpoint|
            delivery = @delivery_repository.upsert_pending(
              id: "whd_#{UUID.random}",
              endpoint_id: endpoint.id,
              event_id: event.event_id,
              event_type: event.event_type,
              payload: payload
            )
            next if delivery.status == "delivered"

            begin
              status = deliver(endpoint, payload, event.event_id, event.event_type)
              @delivery_repository.mark_delivered(delivery.id, status)
            rescue ex
              @delivery_repository.mark_failed(delivery.id, ex.message || "delivery_error", nil)
              failures << endpoint.id
            end
          end

          raise "webhook_delivery_failed endpoints=#{failures.join(",")}" unless failures.empty?
        end

        private def deliver(endpoint : Infrastructure::DB::WebhookEndpointRecord, payload : String,
                            event_id : String, event_type : String) : Int32
          uri = URI.parse(endpoint.url)
          raise "invalid webhook url" unless uri.host

          signature = sign(endpoint.secret, payload)
          headers = HTTP::Headers{
            "Content-Type"        => "application/json",
            "User-Agent"          => "#{@settings.service_name}/webhooks",
            "X-Webhook-Event"     => event_type,
            "X-Webhook-Event-Id"  => event_id,
            "X-Webhook-Signature" => "sha256=#{signature}",
          }

          client = HTTP::Client.new(uri)
          client.connect_timeout = 5.seconds
          client.read_timeout = 10.seconds
          begin
            response = client.post(uri.request_target, headers: headers, body: payload)
            status = response.status_code
            raise "webhook endpoint returned #{status}" unless (200...300).includes?(status)
            status
          ensure
            client.close rescue nil
          end
        end

        private def sign(secret : String, payload : String) : String
          OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, payload)
        end

        private def view(record : Infrastructure::DB::WebhookEndpointRecord) : EndpointView
          EndpointView.new(
            id: record.id,
            organization_id: record.organization_id,
            url: record.url,
            description: record.description,
            event_types: record.event_types,
            active: record.active,
            created_at: record.created_at.to_rfc3339
          )
        end

        private def validate_url!(url : String) : Nil
          raise Core::Errors::ValidationError.new("Webhook URL is required.") if url.strip.empty?
          uri = URI.parse(url.strip)
          raise Core::Errors::ValidationError.new("Webhook URL must be absolute http(s).") unless uri.host
          raise Core::Errors::ValidationError.new("Webhook URL must be absolute http(s).") unless uri.scheme == "http" || uri.scheme == "https"
        rescue URI::Error
          raise Core::Errors::ValidationError.new("Webhook URL must be absolute http(s).")
        end
      end
    end
  end
end
