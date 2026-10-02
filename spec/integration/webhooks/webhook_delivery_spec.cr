require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/webhook_receiver"

module KemalcrStarter
  describe "Webhook delivery pipeline" do
    it "delivers signed product.created events to a subscribed endpoint" do
      TestDatabase.truncate_all!

      settings = App.settings
      hasher = Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)
      users = Infrastructure::DB::UserRepository.new(TestDatabase.database)
      orgs = Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      memberships = Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)

      users.create(id: "usr_wh", email: "wh@example.com", name: "WH", password_digest: hasher.hash("Passw0rd!"))
      orgs.create(id: "org_wh", slug: "org-wh", name: "Webhook Org", owner_user_id: "usr_wh")
      memberships.create(id: "mem_wh", organization_id: "org_wh", user_id: "usr_wh", role: "owner", status: "active")

      receiver = WebhookReceiver.new("whsec_test_secret")
      port = receiver.start

      endpoints = Infrastructure::DB::WebhookEndpointRepository.new(TestDatabase.database)
      endpoints.create(
        id: "whk_e2e",
        organization_id: "org_wh",
        url: "http://127.0.0.1:#{port}/hooks",
        secret: "whsec_test_secret",
        description: "e2e",
        event_types: ["product.created"],
        created_by: "usr_wh"
      )

      product_service = Modules::Products::ProductService.new(
        settings,
        TestDatabase.database,
        Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
      )
      product_service.create_product("usr_wh", "org_wh", "SKU-E2E", "E2E Product", nil, 500, "USD")

      handler = Modules::Webhooks::DeliveryHandler.new(
        Modules::Webhooks::WebhookService.new(settings, TestDatabase.database)
      )
      outbox = Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
      events = outbox.next_batch(10)
      events.size.should eq(1)

      record = events.first
      event = ReconstitutedEventForSpec.new(record)
      handler.handle(event)

      received = receiver.wait_for_request
      payload = JSON.parse(received.body)
      payload["event_type"].as_s.should eq("product.created")
      payload["data"]["sku"].as_s.should eq("SKU-E2E")

      received.headers["X-Webhook-Event"]?.should eq("product.created")
      received.headers["X-Webhook-Event-Id"]?.should eq(payload["event_id"].as_s)

      signature = received.headers["X-Webhook-Signature"]?.not_nil!
      receiver.verify_signature(received.body, signature).should be_true

      deliveries = Infrastructure::DB::WebhookDeliveryRepository.new(TestDatabase.database)
        .list_for_endpoint("whk_e2e")
      deliveries.size.should eq(1)
      deliveries.first.status.should eq("delivered")
      deliveries.first.response_status.should eq(200)
    end

    it "raises for failed delivery so outbox can retry" do
      TestDatabase.truncate_all!

      settings = App.settings
      users = Infrastructure::DB::UserRepository.new(TestDatabase.database)
      orgs = Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      memberships = Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
      hasher = Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)

      users.create(id: "usr_wh2", email: "wh2@example.com", name: "WH2", password_digest: hasher.hash("Passw0rd!"))
      orgs.create(id: "org_wh2", slug: "org-wh2", name: "Webhook Org 2", owner_user_id: "usr_wh2")
      memberships.create(id: "mem_wh2", organization_id: "org_wh2", user_id: "usr_wh2", role: "owner", status: "active")

      endpoints = Infrastructure::DB::WebhookEndpointRepository.new(TestDatabase.database)
      endpoints.create(
        id: "whk_fail",
        organization_id: "org_wh2",
        url: "http://127.0.0.1:1/hooks",
        secret: "secret",
        description: nil,
        event_types: ["product.created"],
        created_by: "usr_wh2"
      )

      product_service = Modules::Products::ProductService.new(
        settings,
        TestDatabase.database,
        Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
      )
      product_service.create_product("usr_wh2", "org_wh2", "SKU-FAIL", "Fail Product", nil, 100, "USD")

      handler = Modules::Webhooks::DeliveryHandler.new(
        Modules::Webhooks::WebhookService.new(settings, TestDatabase.database)
      )
      outbox = Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
      events = outbox.next_batch(10)
      record = events.first

      expect_raises(Exception, /webhook_delivery_failed/) do
        handler.handle(ReconstitutedEventForSpec.new(record))
      end

      deliveries = Infrastructure::DB::WebhookDeliveryRepository.new(TestDatabase.database)
        .list_for_endpoint("whk_fail")
      deliveries.first.status.should eq("failed")
    end
  end

  # Minimal DomainEvent reconstruction for handler tests (mirrors outbox publisher).
  class ReconstitutedEventForSpec < Core::Events::DomainEvent
    getter stored_event_type : String
    getter stored_aggregate_type : String
    getter payload : JSON::Any

    def initialize(record : Infrastructure::DB::OutboxEventRecord)
      @stored_event_type = record.event_type
      @stored_aggregate_type = record.aggregate_type
      @payload = JSON.parse(record.event_data)
      @stored_id = record.id
      @stored_created_at = record.created_at
      super(
        event_type: record.event_type,
        aggregate_type: record.aggregate_type,
        aggregate_id: record.aggregate_id,
        correlation_id: record.correlation_id,
        causation_id: record.causation_id,
        organization_id: record.organization_id
      )
    end

    def event_type : String
      @stored_event_type
    end

    def aggregate_type : String
      @stored_aggregate_type
    end

    def event_data : JSON::Any
      @payload
    end

    def event_id : String
      @stored_id
    end

    def timestamp : Time
      @stored_created_at
    end
  end
end
