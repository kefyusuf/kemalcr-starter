module KemalcrStarter
  module Modules
    module Billing
      class BillingService
        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database,
                       @billing_adapter : Infrastructure::Billing::BillingAdapter)
          @rbac_service = Core::Rbac::AuthorizationService.new(
            Infrastructure::DB::RbacRepository.new(@database)
          )
          @organization_repository = Infrastructure::DB::OrganizationRepository.new(@database)
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
      end
    end
  end
end
