require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"

describe KemalcrStarter::Infrastructure::DB::ApiKeyRepository do
  repo = KemalcrStarter::Infrastructure::DB::ApiKeyRepository.new(TestDatabase.database)
  user_repo = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  org_repo = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    user_repo.create("usr_key_001", "owner@example.com", "Owner", "digest")
    org_repo.create("org_key_001", "acme", "Acme Inc.", "usr_key_001")
  end

  it "creates and reads back an API key" do
    created = repo.create("key_repo_001", "org_key_001", "My Key", "kma_test", "hash_value")
    created.id.should eq "key_repo_001"
    created.name.should eq "My Key"
    created.key_prefix.should eq "kma_test"
  end

  it "finds active key by prefix" do
    repo.create("key_repo_002", "org_key_001", "Test", "kma_find", "hash")
    found = repo.find_active_by_prefix("kma_find")
    found.should_not be_nil
    found.not_nil!.id.should eq "key_repo_002"
  end

  it "counts active keys for an organization" do
    repo.create("key_repo_003", "org_key_001", "Key A", "kma_a", "hash_a")
    repo.create("key_repo_004", "org_key_001", "Key B", "kma_b", "hash_b")
    count = repo.count_active_for_organization("org_key_001")
    count.should eq 2
  end

  it "lists active keys with pagination" do
    repo.create("key_repo_005", "org_key_001", "Key C", "kma_c", "hash_c")
    repo.create("key_repo_006", "org_key_001", "Key D", "kma_d", "hash_d")
    results = repo.list_active_for_organization("org_key_001", limit: 1, offset: 0)
    results.size.should eq 1
  end

  it "revokes a key" do
    repo.create("key_repo_007", "org_key_001", "Revocable", "kma_rev", "hash")
    revoked = repo.revoke("key_repo_007", Time.utc)
    revoked.should_not be_nil
    revoked.not_nil!.revoked_at.should_not be_nil
  end

  it "returns nil for revoked key" do
    repo.create("key_repo_008", "org_key_001", "Gone", "kma_gone", "hash")
    repo.revoke("key_repo_008", Time.utc)
    found = repo.find_active_by_prefix("kma_gone")
    found.should be_nil
  end
end
