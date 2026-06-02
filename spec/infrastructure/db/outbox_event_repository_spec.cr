require "spec"
require "../../spec_helper"
require "../../support/event_helpers"

private def repo
  KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
end

private def create_test_event(correlation_id : String? = nil, causation_id : String? = nil)
  TestOrganizationCreated.new(
    aggregate_id: "org-#{UUID.random.to_s[0..7]}",
    name: "Test Org",
    owner_id: "user-1",
    correlation_id: correlation_id,
    causation_id: causation_id
  )
end

describe KemalcrStarter::Infrastructure::DB::OutboxEventRepository do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
  end

  describe "#create" do
    it "inserts an event into the outbox table" do
      event = create_test_event
      repo.create(event)
      saved = repo.find(event.event_id)
      saved.should_not be_nil
      saved.not_nil!.event_type.should eq(event.event_type)
    end

    it "persists event_data as JSON" do
      event = create_test_event
      repo.create(event)
      saved = repo.find(event.event_id)
      saved.not_nil!.event_data.should contain("Test Org")
    end

    it "persists correlation_id when provided" do
      event = create_test_event(correlation_id: "req_test123")
      repo.create(event)
      saved = repo.find(event.event_id)
      saved.not_nil!.correlation_id.should eq("req_test123")
    end

    it "defaults status to pending" do
      event = create_test_event
      repo.create(event)
      saved = repo.find(event.event_id)
      saved.not_nil!.status.should eq("pending")
    end

    it "defaults attempts to 0" do
      event = create_test_event
      repo.create(event)
      saved = repo.find(event.event_id)
      saved.not_nil!.attempts.should eq(0)
    end
  end

  describe "#create with connection" do
    it "inserts event within a transaction" do
      event = create_test_event
      repo.transaction do |txn|
        conn = txn.connection
        repo.create(event, connection: conn)
      end
      saved = repo.find(event.event_id)
      saved.should_not be_nil
    end

    it "rolls back event when transaction fails" do
      event = create_test_event
      expect_raises(Exception) do
        repo.transaction do |txn|
          conn = txn.connection
          repo.create(event, connection: conn)
          raise "force rollback"
        end
      end
      saved = repo.find(event.event_id)
      saved.should be_nil
    end
  end

  describe "#next_batch" do
    it "returns pending events ordered by created_at" do
      event1 = create_test_event
      event2 = create_test_event
      repo.create(event1)
      sleep 0.01
      repo.create(event2)
      batch = repo.next_batch(10)
      batch.size.should eq(2)
      batch[0].id.should eq(event1.event_id)
      batch[1].id.should eq(event2.event_id)
    end

    it "respects batch_size limit" do
      3.times { repo.create(create_test_event) }
      batch = repo.next_batch(2)
      batch.size.should eq(2)
    end

    it "does not return dispatched events" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      repo.mark_dispatched(event.event_id)
      second_batch = repo.next_batch(10)
      second_batch.any? { |e| e.id == event.event_id }.should be_false
    end

    it "does not return dead_letter events" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      repo.mark_dead(event.event_id, "test error")
      second_batch = repo.next_batch(10)
      second_batch.any? { |e| e.id == event.event_id }.should be_false
    end

    it "sets status to in_progress after claiming" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      saved = repo.find(event.event_id)
      saved.not_nil!.status.should eq("in_progress")
    end

    it "sets locked_at after claiming" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      saved = repo.find(event.event_id)
      saved.not_nil!.locked_at.should_not be_nil
    end

    it "sets polled_at after claiming" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      saved = repo.find(event.event_id)
      saved.not_nil!.polled_at.should_not be_nil
    end
  end

  describe "#mark_dispatched" do
    it "updates status to dispatched" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      repo.mark_dispatched(event.event_id)
      saved = repo.find(event.event_id)
      saved.not_nil!.status.should eq("dispatched")
    end

    it "clears locked_at" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      repo.mark_dispatched(event.event_id)
      saved = repo.find(event.event_id)
      saved.not_nil!.locked_at.should be_nil
    end
  end

  describe "#increment_retry" do
    it "increments attempts count" do
      event = create_test_event
      repo.create(event)
      repo.increment_retry(event.event_id, "error msg")
      saved = repo.find(event.event_id)
      saved.not_nil!.attempts.should eq(1)
    end

    it "records error message" do
      event = create_test_event
      repo.create(event)
      repo.increment_retry(event.event_id, "something broke")
      saved = repo.find(event.event_id)
      saved.not_nil!.last_error.should eq("something broke")
    end

    it "clears locked_at after retry" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      repo.increment_retry(event.event_id, "retry")
      saved = repo.find(event.event_id)
      saved.not_nil!.locked_at.should be_nil
    end
  end

  describe "#mark_dead" do
    it "updates status to dead_letter" do
      event = create_test_event
      repo.create(event)
      repo.next_batch(10)
      repo.mark_dead(event.event_id, "fatal error")
      saved = repo.find(event.event_id)
      saved.not_nil!.status.should eq("dead_letter")
    end

    it "records failure reason" do
      event = create_test_event
      repo.create(event)
      repo.mark_dead(event.event_id, "fatal error")
      saved = repo.find(event.event_id)
      saved.not_nil!.last_error.should eq("fatal error")
    end
  end

  describe "transactional atomicity" do
    it "creates event and business data in same transaction" do
      event = create_test_event
      repo.transaction do |txn|
        conn = txn.connection
        outbox_repo = KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(conn)
        outbox_repo.create(event, connection: conn)
      end
      saved = repo.find(event.event_id)
      saved.should_not be_nil
    end
  end
end
