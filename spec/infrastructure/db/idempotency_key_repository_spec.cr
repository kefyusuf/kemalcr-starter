require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"

describe KemalcrStarter::Infrastructure::DB::IdempotencyKeyRepository do
  repo = KemalcrStarter::Infrastructure::DB::IdempotencyKeyRepository.new(TestDatabase.database)

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
  end

  it "creates and finds an idempotency key" do
    repo.create(id: "key-001", scope: "POST", idempotency_key: "idem-001", request_fingerprint: "fp-001", locked_until: Time.utc + Time::Span.new(seconds: 30))
    record = repo.find("POST", "idem-001")
    record.should_not be_nil
    record.not_nil!.locked_until.should_not be_nil
  end

  it "returns nil for missing key" do
    repo.find("POST", "nonexistent").should be_nil
  end

  it "completes an idempotency key with response data" do
    repo.create(id: "key-002", scope: "POST", idempotency_key: "idem-002", request_fingerprint: "fp-002", locked_until: Time.utc + Time::Span.new(seconds: 30))
    completed = repo.complete("key-002", 200, "{}")
    completed.should_not be_nil
    completed.not_nil!.response_status.should eq 200
    completed.not_nil!.response_body_ref.should eq "{}"
  end

  it "scopes idempotency keys" do
    repo.create(id: "key-003", scope: "POST", idempotency_key: "idem-003", request_fingerprint: "fp-003", locked_until: Time.utc + Time::Span.new(seconds: 30))
    repo.create(id: "key-004", scope: "PATCH", idempotency_key: "idem-003", request_fingerprint: "fp-004", locked_until: Time.utc + Time::Span.new(seconds: 30))
    record_post = repo.find("POST", "idem-003")
    record_patch = repo.find("PATCH", "idem-003")
    record_post.should_not be_nil
    record_patch.should_not be_nil
  end
end
