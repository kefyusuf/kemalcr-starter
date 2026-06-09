require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"

describe KemalcrStarter::Infrastructure::DB::UserSessionRepository do
  repo = KemalcrStarter::Infrastructure::DB::UserSessionRepository.new(TestDatabase.database)
  user_repo = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    user_repo.create("usr_ses_001", "session@example.com", "Session User", "digest")
  end

  it "creates and finds a session" do
    repo.create(id: "ses_repo_001", user_id: "usr_ses_001", session_family_id: "fam_001", refresh_token_hash: "hash", expires_at: Time.utc + 3600.seconds)
    found = repo.find("ses_repo_001")
    found.should_not be_nil
    found.not_nil!.user_id.should eq "usr_ses_001"
  end

  it "checks active session" do
    repo.create(id: "ses_repo_002", user_id: "usr_ses_001", session_family_id: "fam_002", refresh_token_hash: "hash", expires_at: Time.utc + 3600.seconds)
    repo.active?("ses_repo_002", "usr_ses_001").should be_true
  end

  it "returns false for revoked session" do
    repo.create(id: "ses_repo_003", user_id: "usr_ses_001", session_family_id: "fam_003", refresh_token_hash: "hash", expires_at: Time.utc + 3600.seconds)
    repo.revoke("ses_repo_003", Time.utc)
    repo.active?("ses_repo_003", "usr_ses_001").should be_false
  end

  it "revokes entire family" do
    repo.create(id: "ses_repo_004", user_id: "usr_ses_001", session_family_id: "fam_004", refresh_token_hash: "hash_a", expires_at: Time.utc + 3600.seconds)
    repo.create(id: "ses_repo_005", user_id: "usr_ses_001", session_family_id: "fam_004", refresh_token_hash: "hash_b", expires_at: Time.utc + 3600.seconds, rotated_from_id: "ses_repo_004")
    repo.revoke_family("fam_004", Time.utc)
    repo.active?("ses_repo_004", "usr_ses_001").should be_false
    repo.active?("ses_repo_005", "usr_ses_001").should be_false
  end

  it "revokes all sessions for a user" do
    repo.create(id: "ses_repo_006", user_id: "usr_ses_001", session_family_id: "fam_006", refresh_token_hash: "hash", expires_at: Time.utc + 3600.seconds)
    repo.create(id: "ses_repo_007", user_id: "usr_ses_001", session_family_id: "fam_007", refresh_token_hash: "hash", expires_at: Time.utc + 3600.seconds)
    repo.revoke_all_for_user("usr_ses_001", Time.utc)
    repo.active?("ses_repo_006", "usr_ses_001").should be_false
    repo.active?("ses_repo_007", "usr_ses_001").should be_false
  end
end
