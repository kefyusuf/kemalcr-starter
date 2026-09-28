require "./spec_helper"
require "./support/db/test_database"

module KemalcrStarter
  describe Modules::Billing::BillingService do
    it "creates a checkout session through the billing adapter" do
      TestDatabase.truncate_all!
      actor_id = "usr_owner"
      org_id = "org_bill"
      hasher = Infrastructure::Crypto::PasswordHasher.new(App.settings.password_pepper, App.settings.password_hash_cost)
      users = Infrastructure::DB::UserRepository.new(TestDatabase.database)
      orgs = Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      memberships = Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)

      users.create(id: actor_id, email: "owner@example.com", name: "Owner", password_digest: hasher.hash("Passw0rd!"))
      orgs.create(id: org_id, slug: org_id, name: "Bill Org", owner_user_id: actor_id)
      memberships.create(id: "mem_1", organization_id: org_id, user_id: actor_id, role: "owner", status: "active")

      adapter = Infrastructure::Billing::NullBillingAdapter.new
      service = Modules::Billing::BillingService.new(App.settings, TestDatabase.database, adapter)

      session = service.create_checkout(actor_id, org_id, "price_123", "https://app.example/success", "https://app.example/cancel")
      session.provider.should eq("null")
      session.url.should contain("session_id=")
      service.adapter_provider.should eq("null")
    end
  end
end
