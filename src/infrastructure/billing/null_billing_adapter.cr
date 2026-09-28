require "uuid"

module KemalcrStarter
  module Infrastructure
    module Billing
      # Default adapter: no external calls. Safe for tests and local dev.
      class NullBillingAdapter < BillingAdapter
        def provider : String
          "null"
        end

        def create_customer(*, email : String, name : String?, organization_id : String) : BillingCustomer
          id = "cus_null_#{UUID.random}"
          Log.info { "billing customer id=#{id} email=#{email} org=#{organization_id}" }
          BillingCustomer.new(id: id, email: email, provider: provider)
        end

        def create_checkout_session(*, customer_id : String, price_id : String, success_url : String, cancel_url : String) : CheckoutSession
          id = "cs_null_#{UUID.random}"
          url = "#{success_url}?session_id=#{id}"
          Log.info { "billing checkout id=#{id} customer=#{customer_id} price=#{price_id}" }
          CheckoutSession.new(id: id, url: url, provider: provider)
        end

        def cancel_subscription(subscription_id : String) : Bool
          Log.info { "billing cancel subscription_id=#{subscription_id}" }
          true
        end
      end
    end
  end
end
