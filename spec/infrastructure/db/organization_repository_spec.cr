require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"

describe KemalcrStarter::Infrastructure::DB::OrganizationRepository do
  repo = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  user_repo = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  mem_repo = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    user_repo.create("usr_org_repo_001", "owner@example.com", "Owner", "digest")
  end

  it "creates and reads back an organization" do
    created = repo.create("org_repo_001", "acme", "Acme Inc.", "usr_org_repo_001")
    created.id.should eq "org_repo_001"
    created.slug.should eq "acme"
    created.name.should eq "Acme Inc."

    found = repo.find("org_repo_001")
    found.should_not be_nil
    found.not_nil!.name.should eq "Acme Inc."
  end

  it "finds active organizations" do
    repo.create("org_repo_002", "globex", "Globex", "usr_org_repo_001")
    found = repo.find_active("org_repo_002")
    found.should_not be_nil
  end

  it "updates slug and name" do
    repo.create("org_repo_003", "old", "Old Name", "usr_org_repo_001")
    updated = repo.update("org_repo_003", "new-slug", "New Name")
    updated.should_not be_nil
    updated.not_nil!.slug.should eq "new-slug"
    updated.not_nil!.name.should eq "New Name"
  end

  it "counts active organizations for a user" do
    repo.create("org_repo_004", "alpha", "Alpha", "usr_org_repo_001")
    repo.create("org_repo_005", "beta", "Beta", "usr_org_repo_001")
    mem_repo.create("mem_org_repo_001", "org_repo_004", "usr_org_repo_001", "owner", joined_at: Time.utc)
    mem_repo.create("mem_org_repo_002", "org_repo_005", "usr_org_repo_001", "member", joined_at: Time.utc)
    count = repo.count_active_for_user("usr_org_repo_001")
    count.should eq 2
  end

  it "lists active organizations for a user with pagination" do
    repo.create("org_repo_006", "first", "First", "usr_org_repo_001")
    repo.create("org_repo_007", "second", "Second", "usr_org_repo_001")
    mem_repo.create("mem_org_repo_003", "org_repo_006", "usr_org_repo_001", "member", joined_at: Time.utc)
    mem_repo.create("mem_org_repo_004", "org_repo_007", "usr_org_repo_001", "member", joined_at: Time.utc)
    results = repo.list_active_for_user("usr_org_repo_001", limit: 1, offset: 0)
    results.size.should eq 1
  end
end
