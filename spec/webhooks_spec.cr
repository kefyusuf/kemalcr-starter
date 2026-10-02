require "./spec_helper"
require "./support/db/test_database"

module KemalcrStarter
  describe Modules::Webhooks::WebhookService do
    it "creates an endpoint and returns a one-time secret" do
      TestDatabase.truncate_all!
      actor_id = "usr_owner"
      org_id = "org_wh"
      WebhookSpecHelpers.seed_org_actor(actor_id, org_id)

      service = Modules::Webhooks::WebhookService.new(App.settings, TestDatabase.database)
      created = service.create_endpoint(
        actor_id,
        org_id,
        "https://example.com/hooks",
        "demo",
        ["identity.user.created"]
      )

      created.secret.size.should be > 20
      created.endpoint.url.should eq("https://example.com/hooks")
      created.endpoint.event_types.should eq(["identity.user.created"])
    end

    it "authorizes only webhook managers" do
      TestDatabase.truncate_all!
      actor_id = "usr_member"
      org_id = "org_wh"
      WebhookSpecHelpers.seed_org_actor(actor_id, org_id, role: "member")

      service = Modules::Webhooks::WebhookService.new(App.settings, TestDatabase.database)
      expect_raises(Core::Errors::ForbiddenError) do
        service.create_endpoint(actor_id, org_id, "https://example.com/hooks", nil, [] of String)
      end
    end

    it "matches endpoints by event type or wildcard" do
      TestDatabase.truncate_all!
      actor_id = "usr_owner"
      org_id = "org_wh"
      WebhookSpecHelpers.seed_org_actor(actor_id, org_id)

      service = Modules::Webhooks::WebhookService.new(App.settings, TestDatabase.database)
      service.create_endpoint(actor_id, org_id, "https://a.example.com", nil, ["identity.user.created"])
      service.create_endpoint(actor_id, org_id, "https://b.example.com", nil, [] of String)

      endpoints = Infrastructure::DB::WebhookEndpointRepository.new(TestDatabase.database)
        .list_active_for_event_type(org_id, "identity.user.created")
      endpoints.size.should eq(2)

      only_login = Infrastructure::DB::WebhookEndpointRepository.new(TestDatabase.database)
        .list_active_for_event_type(org_id, "identity.user.logged_in")
      only_login.size.should eq(1)
      only_login.first.url.should eq("https://b.example.com")
    end
  end

  module WebhookSpecHelpers
    extend self

    def WebhookSpecHelpers.seed_org_actor(user_id : String, organization_id : String, role : String = "owner") : Nil
      hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(
        KemalcrStarter::App.settings.password_pepper,
        KemalcrStarter::App.settings.password_hash_cost
      )
      users = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
      orgs = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      memberships = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)

      users.create(id: user_id, email: "#{user_id}@example.com", name: user_id, password_digest: hasher.hash("Passw0rd!"))
      orgs.create(id: organization_id, slug: organization_id, name: "Org", owner_user_id: user_id)
      memberships.create(
        id: "mem_#{user_id}",
        organization_id: organization_id,
        user_id: user_id,
        role: role,
        status: "active"
      )
    end
  end
end
