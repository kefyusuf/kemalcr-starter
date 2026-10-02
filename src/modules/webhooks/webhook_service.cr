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
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil,
                       destination : Infrastructure::Http::WebhookDestination? = nil)
          @destination = destination || Infrastructure::Http::WebhookDestination.new(@settings)
          @endpoint_repository = Infrastructure::DB::WebhookEndpointRepository.new(@database)
          @delivery_repository = Infrastructure::DB::WebhookDeliveryRepository.new(@database)
          @rbac_service = Core::Rbac::AuthorizationService.new(
            Infrastructure::DB::RbacRepository.new(@database)
          )
        end

        def create_endpoint(actor_id : String, organization_id : String, url : String,
                            description : String?, event_types : Array(String)) : CreatedEndpoint
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::WebhookManage)
          @destination.validate!(url)

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
          endpoints = @endpoint_repository.list_active_for_event_type(event.event_type)
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
          uri = @destination.validate!(endpoint.url)
          address = @destination.resolve!(uri)

          signature = sign(endpoint.secret, payload)
          headers = HTTP::Headers{
            "Content-Type"        => "application/json",
            "User-Agent"          => "#{@settings.service_name}/webhooks",
            "X-Webhook-Event"     => event_type,
            "X-Webhook-Event-Id"  => event_id,
            "X-Webhook-Signature" => "sha256=#{signature}",
          }

          host = uri.hostname.not_nil!
          headers["Host"] = uri.port ? "#{uri.host}:#{uri.port}" : uri.host.not_nil!
          tcp = TCPSocket.new(address.family)
          client : HTTP::Client? = nil
          begin
            tcp.connect(address, timeout: 5.seconds)
            tcp.read_timeout = 10.seconds
            tcp.write_timeout = 10.seconds
            io = if uri.scheme == "https"
                   OpenSSL::SSL::Socket::Client.new(tcp, context: OpenSSL::SSL::Context::Client.new, sync_close: true, hostname: host)
                 else
                   tcp
                 end
            client = HTTP::Client.new(io, host, address.port)
            client.compress = false
            status = client.post(uri.request_target, headers: headers, body: payload) { |response| response.status_code }
            raise "webhook endpoint returned #{status}" unless (200...300).includes?(status)
            status
          ensure
            client.try(&.close) rescue nil
            tcp.close rescue nil
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
      end
    end
  end
end
