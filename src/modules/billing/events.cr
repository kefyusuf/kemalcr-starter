module KemalcrStarter
  module Modules
    module Billing
      class BillingCheckoutCompleted < Core::Events::DomainEvent
        getter event_type : String = "billing.checkout.completed"
        getter aggregate_type : String = "billing_checkout"
        getter organization_id : String?
        getter session_id : String

        def initialize(@aggregate_id : String, @session_id : String, @organization_id : String?, correlation_id : String? = nil)
          super(event_type: "billing.checkout.completed", aggregate_type: "billing_checkout",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({session_id: @session_id, organization_id: @organization_id}.to_json)
        end
      end

      class BillingSubscriptionUpdated < Core::Events::DomainEvent
        getter event_type : String = "billing.subscription.updated"
        getter aggregate_type : String = "billing_subscription"
        getter subscription_id : String
        getter status : String

        def initialize(@aggregate_id : String, @subscription_id : String, @status : String, correlation_id : String? = nil)
          super(event_type: "billing.subscription.updated", aggregate_type: "billing_subscription",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({subscription_id: @subscription_id, status: @status}.to_json)
        end
      end
    end
  end
end
