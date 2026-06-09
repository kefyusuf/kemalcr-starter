require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"

describe KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository do
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!

    hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(
      KemalcrStarter::App.settings.password_pepper,
      KemalcrStarter::App.settings.password_hash_cost
    )

    user_repository.create("usr_scope_001", "scope@example.com", "Scope User", hasher.hash("supersecret"))
    organization_repository.create("org_scope_001", "acme", "Acme Inc.", "usr_scope_001")
    organization_repository.create("org_scope_002", "globex", "Globex", "usr_scope_001")

    membership_repository.create("mem_scope_001", "org_scope_001", "usr_scope_001", "owner")
    membership_repository.create("mem_scope_002", "org_scope_002", "usr_scope_001", "member")
  end

  it "scopes membership lookup to the requested organization" do
    membership = membership_repository.find_active_for_user_and_organization("usr_scope_001", "org_scope_002")

    membership.should_not be_nil
    membership.not_nil!.organization_id.should eq "org_scope_002"
    membership.not_nil!.role.should eq "member"
  end
end
