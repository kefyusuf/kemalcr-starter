require "spec"
require "../../spec_helper"
require "../../support/event_helpers"
require "redis"

class TestEventHandler
  include KemalcrStarter::Core::Events::EventHandler

  getter handled_events : Array(KemalcrStarter::Core::Events::DomainEvent) = [] of KemalcrStarter::Core::Events::DomainEvent
  getter should_fail : Bool = false
  property fail_count : Int32 = 0

  def initialize(@should_fail : Bool = false)
  end

  def handle(event : KemalcrStarter::Core::Events::DomainEvent) : Nil
    if @should_fail
      @fail_count += 1
      raise "handler failure ##{@fail_count}"
    end
    @handled_events << event
  end
end

private def with_publisher(**kwargs)
  registry = KemalcrStarter::Core::Events::HandlerRegistry.new
  repo = KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
  publisher = KemalcrStarter::Infrastructure::Outbox::OutboxPublisher.new(
    repository: repo,
    handler_registry: registry,
    **kwargs
  )
  {publisher: publisher, registry: registry, repo: repo}
end

describe KemalcrStarter::Infrastructure::Outbox::OutboxPublisher do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
  end

  describe "polling" do
    it "polls and dispatches pending events" do
      ctx = with_publisher(poll_interval: 0.1.seconds)
      event = TestOrganizationCreated.new("org-1", "Acme", "user-1")
      handler = TestEventHandler.new
      ctx[:registry].register("test.organization.created", handler)

      ctx[:repo].create(event)
      ctx[:publisher].process_now!

      handler.handled_events.size.should eq(1)
      handler.handled_events.first.event_type.should eq("test.organization.created")
    end

    it "marks event as dispatched after successful handling" do
      ctx = with_publisher
      event = TestOrganizationCreated.new("org-1", "Acme", "user-1")
      handler = TestEventHandler.new
      ctx[:registry].register("test.organization.created", handler)

      ctx[:repo].create(event)
      ctx[:publisher].process_now!

      saved = ctx[:repo].find(event.event_id)
      saved.not_nil!.status.should eq("dispatched")
    end

    it "dispatches multiple events in a batch" do
      ctx = with_publisher(batch_size: 10)
      handler = TestEventHandler.new
      ctx[:registry].register("test.organization.created", handler)

      events = 3.times.map { TestOrganizationCreated.new("org-#{_1}", "Org #{_1}", "user-1") }.to_a
      events.each { |e| ctx[:repo].create(e) }
      ctx[:publisher].process_now!

      handler.handled_events.size.should eq(3)
    end

    it "skips events with no registered handlers" do
      ctx = with_publisher
      event = TestOrganizationCreated.new("org-1", "Acme", "user-1")
      ctx[:repo].create(event)
      ctx[:publisher].process_now!

      saved = ctx[:repo].find(event.event_id)
      saved.not_nil!.status.should eq("dispatched")
    end
  end

  describe "retry on handler failure" do
    it "increments retry count when handler fails" do
      ctx = with_publisher(max_retries: 3)
      event = TestOrganizationCreated.new("org-1", "Acme", "user-1")
      handler = TestEventHandler.new(should_fail: true)
      ctx[:registry].register("test.organization.created", handler)

      ctx[:repo].create(event)
      ctx[:publisher].process_now!

      saved = ctx[:repo].find(event.event_id)
      saved.not_nil!.attempts.should eq(1)
    end

    it "moves to dead letter after max retries" do
      ctx = with_publisher(max_retries: 2)
      event = TestOrganizationCreated.new("org-1", "Acme", "user-1")
      handler = TestEventHandler.new(should_fail: true)
      ctx[:registry].register("test.organization.created", handler)

      ctx[:repo].create(event)
      # Simulate 3 dispatch attempts (max_retries=2 means 3rd attempt → dead letter)
      3.times { ctx[:publisher].process_now! }

      saved = ctx[:repo].find(event.event_id)
      saved.not_nil!.status.should eq("dead_letter")
    end
  end

  describe "start/stop lifecycle" do
    it "gracefully stops the publisher" do
      ctx = with_publisher
      ctx[:publisher].start
      ctx[:publisher].running?.should be_true
      ctx[:publisher].stop
      ctx[:publisher].running?.should be_false
    end
  end

  describe "stats tracking" do
    it "tracks dispatched count" do
      ctx = with_publisher
      handler = TestEventHandler.new
      ctx[:registry].register("test.organization.created", handler)
      event = TestOrganizationCreated.new("org-1", "Acme", "user-1")

      ctx[:repo].create(event)
      ctx[:publisher].process_now!

      ctx[:publisher].stats.dispatched.should eq(1)
    end
  end
end
