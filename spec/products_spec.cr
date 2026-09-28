require "./spec_helper"
require "./support/db/test_database"

module KemalcrStarter
  module ProductSpecHelpers
    extend self

    def seed_org_actor(user_id : String, organization_id : String, role : String = "owner") : Nil
      hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(
        KemalcrStarter::App.settings.password_pepper,
        KemalcrStarter::App.settings.password_hash_cost
      )
      users = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
      orgs = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      memberships = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)

      users.create(id: user_id, email: "#{user_id}@example.com", name: user_id, password_digest: hasher.hash("Passw0rd!")) unless users.find_credentials(user_id)
      orgs.create(id: organization_id, slug: organization_id, name: "Org", owner_user_id: user_id) unless orgs.find(organization_id)
      memberships.create(
        id: "mem_#{user_id}",
        organization_id: organization_id,
        user_id: user_id,
        role: role,
        status: "active"
      )
    end
  end

  describe Modules::Products::ProductService do
    it "creates, lists, updates, and deletes a product" do
      TestDatabase.truncate_all!
      actor_id = "usr_owner"
      org_id = "org_prd"
      ProductSpecHelpers.seed_org_actor(actor_id, org_id)

      service = Modules::Products::ProductService.new(App.settings, TestDatabase.database)

      created = service.create_product(actor_id, org_id, "SKU-1", "Widget", "A widget", 1999, "usd")
      created.sku.should eq("SKU-1")
      created.price_cents.should eq(1999)
      created.currency.should eq("USD")

      listed = service.list_products(actor_id, org_id)
      listed.size.should eq(1)

      updated = service.update_product(actor_id, org_id, created.id, "Widget Pro", nil, 2999, "active")
      updated.not_nil!.name.should eq("Widget Pro")
      updated.not_nil!.price_cents.should eq(2999)

      service.delete_product(actor_id, org_id, created.id).should be_true
      service.list_products(actor_id, org_id).size.should eq(0)
    end

    it "requires ProductManage for writes and allows members to list" do
      TestDatabase.truncate_all!
      owner_id = "usr_owner"
      member_id = "usr_member"
      org_id = "org_prd"
      ProductSpecHelpers.seed_org_actor(owner_id, org_id, role: "owner")
      ProductSpecHelpers.seed_org_actor(member_id, org_id, role: "member")

      service = Modules::Products::ProductService.new(App.settings, TestDatabase.database)
      service.create_product(owner_id, org_id, "SKU-1", "Widget", nil, 100, "USD")

      service.list_products(member_id, org_id).size.should eq(1)
      expect_raises(Core::Errors::ForbiddenError) do
        service.create_product(member_id, org_id, "SKU-2", "Nope", nil, 100, "USD")
      end
    end
  end
end
