require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/event_helpers"

private def claim_repository
  KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
end

private def seed_claim_event(name : String = "Claim")
  event = TestOrganizationCreated.new("org-claim", name, "user-claim")
  claim_repository.create(event)
  event
end

private class RecoveryInterleavingHandler
  include KemalcrStarter::Core::Events::EventHandler

  def initialize(@action : Proc(Nil), @fail : Bool)
  end

  def handle(event : KemalcrStarter::Core::Events::DomainEvent) : Nil
    @action.call
    raise "old handler failed" if @fail
  end
end

private class PausedClaimRepository < KemalcrStarter::Infrastructure::DB::OutboxEventRepository
  def initialize(database : ::DB::Database, @selected : Channel(Nil), @resume : Channel(Nil))
    super(database)
  end

  protected def many(sql : String, *args, &block : ::DB::ResultSet -> T) : Array(T) forall T
    rows = super(sql, *args) { |rs| yield rs }
    @selected.send(nil)
    select
    when @resume.receive
    when timeout(5.seconds)
      raise "claim interleaving was not released"
    end
    rows
  end
end

private def stale_worker_scenario(fail : Bool, max_retries : Int32, retry_new_owner : Bool = true)
  event = seed_claim_event
  registry = KemalcrStarter::Core::Events::HandlerRegistry.new
  action = -> {
    TestDatabase.database.exec "UPDATE outbox_events SET locked_at = NOW() - INTERVAL '1 minute' WHERE id = $1", event.event_id
    claim_repository.reclaim_stale_in_progress.should eq 1
    claim_repository.next_batch(1).size.should eq 1
    claim_repository.increment_retry(event.event_id, "new owner retry", 60) if retry_new_owner
    nil
  }
  registry.register(event.event_type, RecoveryInterleavingHandler.new(action, fail))
  publisher = KemalcrStarter::Infrastructure::Outbox::OutboxPublisher.new(claim_repository, registry, max_retries: max_retries)
  publisher.process_now!.should eq 1
  {event.event_id, publisher}
end

describe "Atomic outbox claims and recovery" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
  end

  after_each do
    TestDatabase.database.exec "ALTER TABLE outbox_events DROP CONSTRAINT IF EXISTS spec_reject_claim"
  end

  it "returns the committed claim state and timestamps rather than pending snapshots" do
    event = seed_claim_event
    claimed = claim_repository.next_batch(1).first
    claimed.id.should eq event.event_id
    claimed.status.should eq "in_progress"
    claimed.locked_at.should_not be_nil
    claimed.polled_at.should_not be_nil
    stored = claim_repository.find(event.event_id).not_nil!
    claimed.locked_at.should eq stored.locked_at
    claimed.polled_at.should eq stored.polled_at
    claimed.updated_at.should eq stored.updated_at
  end

  it "rolls back every claim when one row in the batch rejects the update" do
    seed_claim_event("First")
    seed_claim_event("Reject")
    TestDatabase.database.exec <<-SQL
      ALTER TABLE outbox_events ADD CONSTRAINT spec_reject_claim
      CHECK (status != 'in_progress' OR event_data->>'name' != 'Reject')
    SQL
    expect_raises(::PQ::PQError, /spec_reject_claim/) { claim_repository.next_batch(2) }
    TestDatabase.database.scalar("SELECT COUNT(*) FROM outbox_events WHERE status = 'pending'").as(Int64).should eq 2
    TestDatabase.database.scalar("SELECT COUNT(*) FROM outbox_events WHERE locked_at IS NOT NULL OR polled_at IS NOT NULL").as(Int64).should eq 0
  end

  it "gives an event to only one claimant when another polls immediately after selection" do
    event = seed_claim_event
    selected = Channel(Nil).new(1)
    resume = Channel(Nil).new(1)
    results = Channel(Array(String) | Exception).new(1)
    repository = PausedClaimRepository.new(TestDatabase.database, selected, resume)
    spawn do
      begin
        results.send(repository.next_batch(1).map(&.id))
      rescue ex
        results.send(ex)
      end
    end
    select
    when selected.receive
    when timeout(5.seconds)
      raise "first claimant did not complete its database query"
    end
    begin
      second = claim_repository.next_batch(1).map(&.id)
    ensure
      resume.send(nil)
    end
    select
    when result = results.receive
      raise result if result.is_a?(Exception)
      (result + second.not_nil!).should eq [event.event_id]
    when timeout(5.seconds)
      raise "first claimant did not finish"
    end
  end

  it "uses a strictly newer claim identity even when the previous poll timestamp is in the future" do
    event = seed_claim_event
    previous = Time.utc + 1.day
    TestDatabase.database.exec "UPDATE outbox_events SET polled_at = $2 WHERE id = $1", event.event_id, previous
    stored_previous = claim_repository.find(event.event_id).not_nil!.polled_at.not_nil!
    claim_repository.next_batch(1).first.polled_at.not_nil!.should be > stored_previous
  end

  it "recovers abandoned claims while preserving retry history and skipping live claims and backoff" do
    abandoned = seed_claim_event("Abandoned")
    live = seed_claim_event("Live")
    delayed = seed_claim_event("Delayed")
    TestDatabase.database.exec "UPDATE outbox_events SET status = 'in_progress', locked_at = NOW() - INTERVAL '1 minute', attempts = 2, last_error = 'previous failure', polled_at = NOW() - INTERVAL '1 minute' WHERE id = $1", abandoned.event_id
    TestDatabase.database.exec "UPDATE outbox_events SET status = 'in_progress', locked_at = NOW() WHERE id = $1", live.event_id
    claim_repository.increment_retry(delayed.event_id, "backoff", 60)
    previous_poll = claim_repository.find(abandoned.event_id).not_nil!.polled_at
    claim_repository.reclaim_stale_in_progress.should eq 1
    recovered = claim_repository.find(abandoned.event_id).not_nil!
    recovered.status.should eq "pending"
    recovered.locked_at.should be_nil
    recovered.polled_at.should eq previous_poll
    recovered.attempts.should eq 2
    recovered.last_error.should eq "previous failure"
    claim_repository.next_batch(10).map(&.id).should eq [abandoned.event_id]
  end

  it "prevents stale successful completion from overwriting a new owner's retry" do
    id, publisher = stale_worker_scenario(false, 5)
    stored = claim_repository.find(id).not_nil!
    stored.status.should eq "pending"
    stored.last_error.should eq "new owner retry"
    stored.attempts.should eq 1
    publisher.stats.dispatched.should eq 0
  end

  it "prevents a stale failure from incrementing the new owner's retry" do
    id, publisher = stale_worker_scenario(true, 5)
    stored = claim_repository.find(id).not_nil!
    stored.attempts.should eq 1
    stored.last_error.should eq "new owner retry"
    publisher.stats.failed.should eq 0
  end

  it "prevents a stale failure from dead-lettering the new owner's event" do
    id, publisher = stale_worker_scenario(true, 0)
    claim_repository.find(id).not_nil!.status.should eq "pending"
    TestDatabase.database.scalar("SELECT COUNT(*) FROM dead_letter_events").as(Int64).should eq 0
    publisher.stats.dead_letter.should eq 0
  end

  { {false, 5, "completion"}, {true, 5, "retry"}, {true, 0, "dead-letter"} }.each do |fail, max_retries, outcome|
    it "fences stale #{outcome} while the new owner's claim is still in progress" do
      id, publisher = stale_worker_scenario(fail, max_retries, retry_new_owner: false)
      stored = claim_repository.find(id).not_nil!
      stored.status.should eq "in_progress"
      stored.attempts.should eq 0
      stored.last_error.should be_nil
      TestDatabase.database.scalar("SELECT COUNT(*) FROM dead_letter_events").as(Int64).should eq 0
      publisher.stats.dispatched.should eq 0
      publisher.stats.failed.should eq 0
      publisher.stats.dead_letter.should eq 0
    end
  end

  it "rolls back a fenced dead-letter transition when PostgreSQL rejects the dead-letter insert" do
    seed_claim_event
    event = claim_repository.next_batch(1).first
    TestDatabase.database.exec "ALTER TABLE dead_letter_events ADD CONSTRAINT spec_reject_dead_letter CHECK (failure_reason != 'reject')"
    begin
      expect_raises(::PQ::PQError, /spec_reject_dead_letter/) { claim_repository.move_to_dead_letter(event, "reject") }
      stored = claim_repository.find(event.id).not_nil!
      stored.status.should eq "in_progress"
      stored.polled_at.should eq event.polled_at
      stored.locked_at.should eq event.locked_at
      TestDatabase.database.scalar("SELECT COUNT(*) FROM dead_letter_events").as(Int64).should eq 0
    ensure
      TestDatabase.database.exec "ALTER TABLE dead_letter_events DROP CONSTRAINT IF EXISTS spec_reject_dead_letter"
    end
    claim_repository.move_to_dead_letter(event, "fatal").should be_true
    claim_repository.move_to_dead_letter(event, "duplicate").should be_false
    claim_repository.find(event.id).not_nil!.status.should eq "dead_letter"
    TestDatabase.database.scalar("SELECT COUNT(*) FROM dead_letter_events").as(Int64).should eq 1
  end

  it "skips rows held by another transaction and claims them after release" do
    first = seed_claim_event("First")
    second = seed_claim_event("Second")
    TestDatabase.database.transaction do |txn|
      txn.connection.query_one("SELECT id FROM outbox_events WHERE id = $1 FOR UPDATE", first.event_id, as: String)
      claim_repository.next_batch(10).map(&.id).should eq [second.event_id]
    end
    claim_repository.next_batch(10).map(&.id).should eq [first.event_id]
  end
end
