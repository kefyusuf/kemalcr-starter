module KemalcrStarter
  module Infrastructure
    module Billing
      record BillingCustomer,
        id : String,
        email : String,
        provider : String

      record CheckoutSession,
        id : String,
        url : String,
        provider : String

      # Payment/billing port. Swap implementations via App.install_billing_adapter.
      abstract class BillingAdapter
        abstract def provider : String

        abstract def create_customer(*, email : String, name : String?, organization_id : String) : BillingCustomer

        abstract def create_checkout_session(*, customer_id : String, price_id : String, success_url : String, cancel_url : String) : CheckoutSession

        abstract def cancel_subscription(subscription_id : String) : Bool
      end
    end
  end
end
