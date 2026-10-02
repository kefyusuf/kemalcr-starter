require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/webhook_receiver"

module KemalcrStarter
  describe "Webhook tenant isolation" do
    before_each do
      TestDatabase.migrate!
      TestDatabase.truncate_all!
    end

    it "delivers only to the owning organization's filtered and wildcard subscriptions" do
      scenario = WebhookTenancyScenario.new
      begin
        scenario.subscribe("whk_owner_filtered", "org_owner", ["product.created"])
        scenario.subscribe("whk_owner_all", "org_owner", [] of String)
        scenario.subscribe("whk_other_filtered", "org_other", ["product.created"])
        scenario.subscribe("whk_other_all", "org_other", [] of String)
        scenario.subscribe("whk_unrelated", "org_owner", ["product.deleted"])
        scenario.subscribe("whk_revoked", "org_owner", [] of String)
        scenario.endpoints.revoke("whk_revoked")

        scenario.dispatch(Modules::Products::ProductCreated.new("prd_owner", "org_owner", "SKU-1", "Private product"))

        scenario.other.requests.should be_empty
        scenario.owner.requests.size.should eq(2)
        scenario.deliveries.list_for_endpoint("whk_other_filtered").should be_empty
        scenario.deliveries.list_for_endpoint("whk_other_all").should be_empty
        scenario.deliveries.list_for_endpoint("whk_unrelated").should be_empty
        scenario.deliveries.list_for_endpoint("whk_revoked").should be_empty
        scenario.deliveries.list_for_endpoint("whk_owner_filtered").first.status.should eq("delivered")
        payload = JSON.parse(scenario.owner.requests.first.body)
        payload["organization_id"]?.try(&.as_s).should eq("org_owner")
        scenario.owner.verify_signature(scenario.owner.requests.first.body, scenario.owner.requests.first.signature.not_nil!).should be_true
      ensure
        scenario.close
      end
    end

    it "does not broadcast global identity events to tenant wildcard subscribers" do
      scenario = WebhookTenancyScenario.new
      begin
        scenario.subscribe("whk_owner", "org_owner", [] of String)
        scenario.subscribe("whk_other", "org_other", [] of String)

        scenario.dispatch(Modules::Identity::UserCreated.new("usr_global", "private@example.com"))

        scenario.owner.requests.should be_empty
        scenario.other.requests.should be_empty
        scenario.deliveries.list_for_endpoint("whk_owner").should be_empty
        scenario.deliveries.list_for_endpoint("whk_other").should be_empty
      ensure
        scenario.close
      end
    end

    it "scopes organization events even when the payload has no organization_id" do
      scenario = WebhookTenancyScenario.new
      begin
        scenario.subscribe("whk_owner", "org_owner", [] of String)
        scenario.subscribe("whk_other", "org_other", [] of String)

        scenario.dispatch(Modules::Organizations::OrganizationUpdated.new("org_owner"), transactional: true)

        scenario.other.requests.should be_empty
        scenario.owner.requests.size.should eq(1)
        JSON.parse(scenario.owner.requests.first.body)["organization_id"]?.try(&.as_s).should eq("org_owner")
      ensure
        scenario.close
      end
    end

    it "does not infer tenant ownership from an unscoped event payload" do
      scenario = WebhookTenancyScenario.new
      begin
        scenario.subscribe("whk_owner", "org_owner", [] of String)
        scenario.subscribe("whk_other", "org_other", [] of String)

        scenario.dispatch(UnscopedWebhookEvent.new)

        scenario.owner.requests.should be_empty
        scenario.other.requests.should be_empty
      ensure
        scenario.close
      end
    end

    it "keeps retry delivery inside the owning organization" do
      scenario = WebhookTenancyScenario.new
      begin
        scenario.subscribe("whk_owner", "org_owner", [] of String)
        scenario.subscribe("whk_other", "org_other", [] of String)
        scenario.owner.response_status = 503
        event = Modules::Products::ProductCreated.new("prd_retry", "org_owner", "SKU-RETRY", "Retry product")

        scenario.dispatch(event)
        scenario.deliveries.list_for_endpoint("whk_owner").first.status.should eq("failed")
        scenario.outbox.find(event.event_id).not_nil!.status.should eq("pending")
        scenario.owner.response_status = 200
        TestDatabase.database.exec("UPDATE outbox_events SET locked_at = NOW() WHERE id = $1", event.event_id)
        scenario.publisher.process_now!.should eq(1)

        scenario.other.requests.should be_empty
        delivery = scenario.deliveries.list_for_endpoint("whk_owner").first
        delivery.status.should eq("delivered")
        delivery.attempt_count.should eq(2)
        scenario.owner.requests.size.should eq(2)
      ensure
        scenario.close
      end
    end

    it "preserves tenant ownership when a dead-letter event is requeued" do
      scenario = WebhookTenancyScenario.new(max_retries: 0)
      begin
        scenario.subscribe("whk_owner", "org_owner", [] of String)
        scenario.subscribe("whk_other", "org_other", [] of String)
        scenario.owner.response_status = 503
        event = Modules::Products::ProductCreated.new("prd_dead", "org_owner", "SKU-DEAD", "Dead letter product")

        scenario.dispatch(event)
        dead_letter = scenario.outbox.list_dead_letters.first
        scenario.outbox.find(event.event_id).not_nil!.status.should eq("dead_letter")
        scenario.owner.response_status = 200
        scenario.outbox.requeue_dead_letter(dead_letter.id).should be_true
        scenario.publisher.process_now!.should eq(1)

        scenario.other.requests.should be_empty
        scenario.owner.requests.size.should eq(2)
        scenario.deliveries.list_for_endpoint("whk_other").should be_empty
        payload = JSON.parse(scenario.owner.requests.last.body)
        scenario.deliveries.find_by_endpoint_event("whk_owner", payload["event_id"].as_s).not_nil!.status.should eq("delivered")
        payload["organization_id"]?.try(&.as_s).should eq("org_owner")
      ensure
        scenario.close
      end
    end
  end

  private class UnscopedWebhookEvent < Core::Events::DomainEvent
    def initialize
      super(event_type: "product.created", aggregate_type: "product", aggregate_id: "prd_legacy")
    end

    def event_data : JSON::Any
      JSON.parse(%({"organization_id":"org_owner","name":"Legacy product"}))
    end
  end

  private class WebhookTenancyScenario
    getter owner : WebhookReceiver
    getter other : WebhookReceiver
    getter endpoints : Infrastructure::DB::WebhookEndpointRepository
    getter deliveries : Infrastructure::DB::WebhookDeliveryRepository
    getter outbox : Infrastructure::DB::OutboxEventRepository
    getter publisher : Infrastructure::Outbox::OutboxPublisher

    def initialize(max_retries : Int32 = 5)
      users = Infrastructure::DB::UserRepository.new(TestDatabase.database)
      orgs = Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
      {"owner", "other"}.each do |name|
        users.create(id: "usr_#{name}", email: "#{name}@example.com", name: name, password_digest: "unused")
        orgs.create(id: "org_#{name}", slug: name, name: name, owner_user_id: "usr_#{name}")
      end

      @owner = WebhookReceiver.new("owner-secret")
      @other = WebhookReceiver.new("other-secret")
      @owner_port = @owner.start
      @other_port = @other.start
      @endpoints = Infrastructure::DB::WebhookEndpointRepository.new(TestDatabase.database)
      @deliveries = Infrastructure::DB::WebhookDeliveryRepository.new(TestDatabase.database)
      @outbox = Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
      registry = Core::Events::HandlerRegistry.new
      registry.register("*", Modules::Webhooks::DeliveryHandler.new(Modules::Webhooks::WebhookService.new(App.settings, TestDatabase.database)))
      @publisher = Infrastructure::Outbox::OutboxPublisher.new(@outbox, registry, max_retries: max_retries)
    end

    def subscribe(id : String, organization_id : String, event_types : Array(String)) : Nil
      receiver = organization_id == "org_owner" ? @owner : @other
      port = organization_id == "org_owner" ? @owner_port : @other_port
      @endpoints.create(id: id, organization_id: organization_id, url: "http://127.0.0.1:#{port}/hooks",
        secret: receiver.secret, description: nil, event_types: event_types, created_by: nil)
    end

    def dispatch(event : Core::Events::DomainEvent, transactional : Bool = false) : Nil
      if transactional
        TestDatabase.database.transaction do |transaction|
          @outbox.create(event, connection: transaction.connection)
        end
      else
        @outbox.create(event)
      end
      @publisher.process_now!.should eq(1)
    end

    def close : Nil
      @owner.stop
      @other.stop
    end
  end
end
