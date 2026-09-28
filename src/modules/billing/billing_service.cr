module KemalcrStarter
  module Modules
    module Billing
      class BillingService
        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database,
                       @billing_adapter : Infrastructure::Billing::BillingAdapter,
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil)
          @rbac_service = Core::Rbac::AuthorizationService.new(
            Infrastructure::DB::RbacRepository.new(@database)
          )
          @organization_repository = Infrastructure::DB::OrganizationRepository.new(@database)
          @webhook_verifier = Infrastructure::Billing::StripeWebhookVerifier.new(
            @settings.stripe_webhook_secret || "",
            @settings.stripe_webhook_tolerance_seconds
          )
        end

        def create_checkout(actor_id : String, organization_id : String, price_id : String,
                            success_url : String, cancel_url : String) : Infrastructure::Billing::CheckoutSession
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::OrganizationUpdate)
          raise Core::Errors::ValidationError.new("price_id is required.") if price_id.strip.empty?

          org = @organization_repository.find(organization_id)
          org_name = org.try(&.name) || organization_id

          customer = @billing_adapter.create_customer(
            email: "billing@#{organization_id}.example",
            name: org_name,
            organization_id: organization_id
          )

          @billing_adapter.create_checkout_session(
            customer_id: customer.id,
            price_id: price_id.strip,
            success_url: success_url,
            cancel_url: cancel_url
          )
        end

        def adapter_provider : String
          @billing_adapter.provider
        end

        # Returns a symbol-like status for the route layer.
        def handle_stripe_webhook(payload : String, signature_header : String?) : String
          secret = @settings.stripe_webhook_secret
          raise Core::Errors::UnauthorizedError.new("Webhook secret not configured.") if secret.nil? || secret.empty?
          raise Core::Errors::UnauthorizedError.new("Invalid webhook signature.") unless @webhook_verifier.verify(payload, signature_header)

          event = JSON.parse(payload)
          event_id = event["id"]?.try(&.as_s) || ""
          event_type = event["type"]?.try(&.as_s) || ""
          object = event["data"]?.try(&.["object"]?)

          case event_type
          when "checkout.session.completed"
            session_id = object.try(&.["id"]?.try(&.as_s)) || event_id
            organization_id = object.try(&.["metadata"]?.try(&.["organization_id"]?.try(&.as_s)))
            publish_event(BillingCheckoutCompleted.new(event_id, session_id, organization_id))
          when "customer.subscription.updated", "customer.subscription.deleted"
            subscription_id = object.try(&.["id"]?.try(&.as_s)) || event_id
            status = object.try(&.["status"]?.try(&.as_s)) || "unknown"
            publish_event(BillingSubscriptionUpdated.new(event_id, subscription_id, status))
          else
            Log.info { "stripe_webhook ignored type=#{event_type} id=#{event_id}" }
          end

          "ok"
        end

        private def publish_event(event : Core::Events::DomainEvent) : Nil
          repo = @event_repository
          repo.try(&.create(event))
        end
      end
    end
  end
end
