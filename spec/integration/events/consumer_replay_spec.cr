require "../../spec_helper"
require "../../support/db/test_database"

private def replay_audit_repository
  KemalcrStarter::Infrastructure::DB::AuditLogRepository.new(TestDatabase.database)
end

private def replay_audit_count : Int64
  TestDatabase.database.scalar("SELECT COUNT(*) FROM audit_logs").as(Int64)
end

private def replay_marker_count : Int64
  TestDatabase.database.scalar("SELECT COUNT(*) FROM processed_events").as(Int64)
end

private def successful_replay(&block : -> Nil) : Nil
  yield
rescue ex
  fail "Expected replay to succeed, got #{ex.class}: #{ex.message}"
end

private def run_replay_migration(direction : String) : Nil
  sql = File.read("db/migrations/016_scope_processed_events_to_consumer.#{direction}.sql")
  TestDatabase.database.transaction do |txn|
    sql.split(';').each do |statement|
      next if statement.strip.empty?
      txn.connection.exec(statement)
    end
  end
end

describe "Durable consumer replay protection" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
  end

  after_each do
    TestDatabase.database.exec "ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS spec_reject_audit"
    TestDatabase.database.exec "ALTER TABLE processed_events DROP CONSTRAINT IF EXISTS spec_reject_processed"
  end

  it "records an organization event once across repeated deliveries" do
    event = KemalcrStarter::Modules::Organizations::OrganizationCreated.new("org_replay", "Replay", "usr_replay")
    handler = KemalcrStarter::Core::Events::OrganizationAuditHandler.new(replay_audit_repository)
    successful_replay { 2.times { handler.handle(event) } }
    replay_audit_count.should eq 1
    replay_marker_count.should eq 1
    row = TestDatabase.database.query_one("SELECT event_id, actor_id, action, resource_id, new_value::text FROM audit_logs", as: {String, String, String, String, String})
    row[0].should eq event.event_id
    row[1].should eq "usr_replay"
    row[2].should eq "organization.created"
    row[3].should eq "org_replay"
    JSON.parse(row[4])["name"].as_s.should eq "Replay"
  end

  it "records membership, API key and identity audit effects once each" do
    repository = replay_audit_repository
    events = [
      KemalcrStarter::Modules::Organizations::MembershipAccepted.new("mem_replay", "org_replay"),
      KemalcrStarter::Modules::ApiKeys::ApiKeyRevoked.new("key_replay", "org_replay"),
      KemalcrStarter::Modules::Identity::UserLoggedIn.new("usr_replay"),
    ] of KemalcrStarter::Core::Events::DomainEvent
    handlers = [
      KemalcrStarter::Core::Events::MembershipAuditHandler.new(repository),
      KemalcrStarter::Core::Events::ApiKeyAuditHandler.new(repository),
      KemalcrStarter::Core::Events::UserAuditHandler.new(repository),
    ] of KemalcrStarter::Core::Events::EventHandler
    successful_replay { events.zip(handlers).each { |event, handler| 2.times { handler.handle(event) } } }
    replay_audit_count.should eq 3
    replay_marker_count.should eq 3
    TestDatabase.database.query_all("SELECT action FROM audit_logs ORDER BY action", as: String).should eq ["api_key.revoked", "membership.accepted", "user.logged_in"]
  end

  it "does not duplicate an audit effect after publisher retries a later handler failure" do
    event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_replay")
    registry = KemalcrStarter::Core::Events::HandlerRegistry.new
    registry.register(event.event_type, KemalcrStarter::Core::Events::OrganizationAuditHandler.new(replay_audit_repository))
    registry.register(event.event_type, ReplayFailingHandler.new)
    outbox = KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
    outbox.create(event)
    publisher = KemalcrStarter::Infrastructure::Outbox::OutboxPublisher.new(outbox, registry)
    publisher.process_now!
    TestDatabase.database.exec "UPDATE outbox_events SET locked_at = NOW() - INTERVAL '1 second' WHERE id = $1", event.event_id
    publisher.process_now!
    replay_audit_count.should eq 1
    replay_marker_count.should eq 1
    outbox.find(event.event_id).not_nil!.attempts.should eq 2
  end

  it "rolls back completion when the audit write fails and permits retry" do
    event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_replay")
    handler = KemalcrStarter::Core::Events::OrganizationAuditHandler.new(replay_audit_repository)
    TestDatabase.database.exec "ALTER TABLE audit_logs ADD CONSTRAINT spec_reject_audit CHECK (action != 'organization.updated')"
    expect_raises(::PQ::PQError, /spec_reject_audit/) { handler.handle(event) }
    replay_audit_count.should eq 0
    replay_marker_count.should eq 0
    TestDatabase.database.exec "ALTER TABLE audit_logs DROP CONSTRAINT spec_reject_audit"
    successful_replay { 2.times { handler.handle(event) } }
    replay_audit_count.should eq 1
    replay_marker_count.should eq 1
  end

  it "does not commit an audit effect when its completion marker is rejected" do
    event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_replay")
    TestDatabase.database.exec "ALTER TABLE processed_events ADD CONSTRAINT spec_reject_processed CHECK (handler_name NOT LIKE 'audit:%')"
    expect_raises(::PQ::PQError, /spec_reject_processed/) do
      KemalcrStarter::Core::Events::OrganizationAuditHandler.new(replay_audit_repository).handle(event)
    end
    replay_audit_count.should eq 0
    replay_marker_count.should eq 0
  end

  it "keeps different event identities separate" do
    repository = replay_audit_repository
    successful_replay do
      2.times do |index|
        repository.create("aud_create_#{index}", "event_created", nil, "created", "item", "item1")
        repository.create("aud_update_#{index}", "event_updated", nil, "updated", "item", "item1")
        repository.create("aud_other_#{index}", "event_other", nil, "created", "item", "item1")
      end
    end
    replay_audit_count.should eq 3
    replay_marker_count.should eq 3
    TestDatabase.database.query_all("SELECT handler_name FROM processed_events ORDER BY handler_name", as: String).should eq ["audit:created", "audit:created", "audit:updated"]
  end

  it "serializes competing consumers into one committed audit effect" do
    event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_replay")
    start = Channel(Nil).new(2)
    results = Channel(Exception?).new(2)
    2.times do
      spawn do
        start.receive
        begin
          KemalcrStarter::Core::Events::OrganizationAuditHandler.new(replay_audit_repository).handle(event)
          results.send(nil)
        rescue ex
          results.send(ex)
        end
      end
    end
    2.times { start.send(nil) }
    2.times do
      select
      when result = results.receive
        result.should be_nil
      when timeout(5.seconds)
        raise "consumer did not finish"
      end
    end
    replay_audit_count.should eq 1
    replay_marker_count.should eq 1
  end

  it "recognizes a matching legacy audit row without creating another effect" do
    TestDatabase.database.exec "INSERT INTO audit_logs (id, event_id, action, resource_type, resource_id) VALUES ('aud_legacy', 'event_legacy', 'created', 'item', 'item1')"
    successful_replay { replay_audit_repository.create("aud_replayed", "event_legacy", nil, "created", "item", "item1") }
    replay_audit_count.should eq 1
    replay_marker_count.should eq 1
  end

  it "persists independent consumer identities for the same event" do
    repository = KemalcrStarter::Infrastructure::DB::ProcessedEventRepository.new(TestDatabase.database)
    repository.mark_processed("event_shared", "consumer:first")
    repository.mark_processed("event_shared", "consumer:second")
    repository.already_processed?("event_shared", "consumer:first").should be_true
    repository.already_processed?("event_shared", "consumer:second").should be_true
    replay_marker_count.should eq 2
  end

  it "commits independent consumer effects using the supplied connection" do
    repository = KemalcrStarter::Infrastructure::DB::ProcessedEventRepository.new(TestDatabase.database)
    {"first", "second"}.each do |name|
      repository.consume_once("event_shared", "consumer:#{name}") do |connection|
        KemalcrStarter::Infrastructure::DB::UserRepository.new(connection).create("usr_#{name}", "#{name}@example.com", name, "unused")
        nil
      end.should be_true
      repository.consume_once("event_shared", "consumer:#{name}") { |_connection| raise "duplicate callback" }.should be_false
    end
    TestDatabase.database.scalar("SELECT COUNT(*) FROM users").as(Int64).should eq 2
    replay_marker_count.should eq 2
  end

  it "rolls back a callback's partial effect and marker after an exception" do
    repository = KemalcrStarter::Infrastructure::DB::ProcessedEventRepository.new(TestDatabase.database)
    expect_raises(Exception, "partial consumer failure") do
      repository.consume_once("event_partial", "consumer:partial") do |connection|
        KemalcrStarter::Infrastructure::DB::UserRepository.new(connection).create("usr_partial", "partial@example.com", "Partial", "unused")
        raise "partial consumer failure"
      end
    end
    TestDatabase.database.scalar("SELECT COUNT(*) FROM users").as(Int64).should eq 0
    replay_marker_count.should eq 0
    repository.consume_once("event_partial", "consumer:partial") do |connection|
      KemalcrStarter::Infrastructure::DB::UserRepository.new(connection).create("usr_partial", "partial@example.com", "Partial", "unused")
      nil
    end.should be_true
    replay_marker_count.should eq 1
  end

  it "rejects conflicting legacy audit content without leaving a completion marker" do
    TestDatabase.database.exec "INSERT INTO audit_logs (id, event_id, action, resource_type, resource_id) VALUES ('aud_legacy', 'event_legacy', 'created', 'item', 'item1')"
    expect_raises(::PQ::PQError, /audit_logs_event_id_key/) { replay_audit_repository.create("aud_conflict", "event_legacy", nil, "updated", "item", "item1") }
    expect_raises(::PQ::PQError, /audit_logs_event_id_key/) { replay_audit_repository.create("aud_resource_conflict", "event_legacy", nil, "created", "item", "other") }
    replay_marker_count.should eq 0
    replay_audit_count.should eq 1
  end

  it "round trips the consumer-key migration without deleting an existing marker" do
    repository = KemalcrStarter::Infrastructure::DB::ProcessedEventRepository.new(TestDatabase.database)
    repository.mark_processed("event_migration", "consumer:first")
    run_replay_migration("down")
    begin
      repository.already_processed?("event_migration", "consumer:first").should be_true
      repository.mark_processed("event_migration", "consumer:second")
      replay_marker_count.should eq 1
    ensure
      run_replay_migration("up")
    end
    repository.mark_processed("event_migration", "consumer:second")
    replay_marker_count.should eq 2
  end

  it "fails down migration without losing markers that require the composite key" do
    repository = KemalcrStarter::Infrastructure::DB::ProcessedEventRepository.new(TestDatabase.database)
    repository.mark_processed("event_migration", "consumer:first")
    repository.mark_processed("event_migration", "consumer:second")
    expect_raises(::PQ::PQError) { run_replay_migration("down") }
    replay_marker_count.should eq 2
    repository.mark_processed("event_migration", "consumer:third")
    replay_marker_count.should eq 3
  end

  {false, true}.each do |rollback_first|
    it "waits for a competing consumer and #{rollback_first ? "takes over after rollback" : "skips after commit"}" do
      repository = KemalcrStarter::Infrastructure::DB::ProcessedEventRepository.new(TestDatabase.database)
      entered = Channel(Nil).new(1)
      release = Channel(Nil).new(1)
      results = Channel({String, Bool | Exception}).new(2)
      spawn do
        begin
          consumed = repository.consume_once("event_competing", "consumer:competing") do |connection|
            KemalcrStarter::Infrastructure::DB::UserRepository.new(connection).create("usr_first", "first@example.com", "First", "unused")
            entered.send(nil)
            select
            when release.receive
            when timeout(5.seconds)
              raise "first consumer was not released"
            end
            raise "first consumer rollback" if rollback_first
            nil
          end
          results.send({"first", consumed})
        rescue ex
          results.send({"first", ex})
        end
      end
      select
      when entered.receive
      when timeout(5.seconds)
        raise "first consumer did not start"
      end
      spawn do
        begin
          consumed = repository.consume_once("event_competing", "consumer:competing") do |connection|
            KemalcrStarter::Infrastructure::DB::UserRepository.new(connection).create("usr_second", "second@example.com", "Second", "unused")
            nil
          end
          results.send({"second", consumed})
        rescue ex
          results.send({"second", ex})
        end
      end
      begin
        deadline = Time.monotonic + 4.seconds
        until TestDatabase.database.scalar("SELECT COUNT(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event = 'transactionid' AND query LIKE '%INSERT INTO processed_events%'").as(Int64) > 0
          raise "second consumer did not wait for the uncommitted marker" if Time.monotonic >= deadline
          sleep 10.milliseconds
        end
      ensure
        release.send(nil)
      end
      outcomes = {} of String => Bool | Exception
      2.times do
        select
        when result = results.receive
          outcomes[result[0]] = result[1]
        when timeout(5.seconds)
          raise "competing consumer did not finish"
        end
      end
      outcomes["second"].should eq rollback_first
      if rollback_first
        outcomes["first"].should be_a(Exception)
      else
        outcomes["first"].should eq true
      end
      TestDatabase.database.query_all("SELECT id FROM users", as: String).should eq [rollback_first ? "usr_second" : "usr_first"]
      replay_marker_count.should eq 1
    end
  end
end

private class ReplayFailingHandler
  include KemalcrStarter::Core::Events::EventHandler

  def handle(event : KemalcrStarter::Core::Events::DomainEvent) : Nil
    raise "later handler failure"
  end
end
