require "../../spec_helper"
require "../../support/db/test_database"

private def atomic_auth_service(with_repository : Bool = true)
  outbox = with_repository ? KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database) : nil
  KemalcrStarter::Modules::Identity::AuthService.new(KemalcrStarter::App.settings, TestDatabase.database, outbox)
end

private def seed_atomic_identity
  service = atomic_auth_service
  KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    .create("usr_atomic", "atomic@example.com", "Atomic", service.password_hasher.hash("OldPass1!"))
  settings = KemalcrStarter::App.settings
  provider = KemalcrStarter::Infrastructure::Jwt::TokenProvider.new(settings.jwt_secret, settings.service_name, settings.jwt_access_ttl_minutes, settings.jwt_refresh_ttl_days)
  tokens = provider.issue_token_pair("usr_atomic", "ses_atomic", "fam_atomic")
  fingerprint = KemalcrStarter::Infrastructure::Crypto::TokenFingerprint.new(settings.password_pepper)
  KemalcrStarter::Infrastructure::DB::UserSessionRepository.new(TestDatabase.database)
    .create("ses_atomic", "usr_atomic", "fam_atomic", fingerprint.digest(tokens.refresh_token), tokens.refresh_expires_at)
  tokens.to_response
end

private def seed_atomic_key
  seed_atomic_identity
  KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database).create("org_atomic", "atomic", "Atomic", "usr_atomic")
  KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database).create("mem_atomic", "org_atomic", "usr_atomic", "owner")
  hasher = KemalcrStarter::Infrastructure::Crypto::ApiKeySecretHasher.new(KemalcrStarter::App.settings.password_pepper)
  secret = hasher.generate_secret
  KemalcrStarter::Infrastructure::DB::ApiKeyRepository.new(TestDatabase.database).create("key_atomic", "org_atomic", "Original", hasher.prefix(secret), hasher.hash(secret))
  secret
end

private def atomic_key_service
  outbox = KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
  rbac = KemalcrStarter::Core::Rbac::AuthorizationService.new(KemalcrStarter::Infrastructure::DB::RbacRepository.new(TestDatabase.database))
  KemalcrStarter::Modules::ApiKeys::ApiKeyService.new(KemalcrStarter::App.settings, TestDatabase.database, outbox, rbac)
end

private def seed_atomic_reset_token : Nil
  fingerprint = KemalcrStarter::Infrastructure::Crypto::TokenFingerprint.new(KemalcrStarter::App.settings.password_pepper)
  repository = KemalcrStarter::Infrastructure::DB::PasswordResetTokenRepository.new(TestDatabase.database)
  repository.create("prt_atomic", "usr_atomic", fingerprint.digest("reset-atomic"), Time.utc + 1.hour)
  repository.create("prt_other", "usr_atomic", fingerprint.digest("reset-other"), Time.utc + 1.hour)
  KemalcrStarter::Infrastructure::DB::UserSessionRepository.new(TestDatabase.database).create("ses_reset_other", "usr_atomic", "fam_reset_other", "other", Time.utc + 1.day)
end

private def reject_identity_key_events! : Nil
  TestDatabase.database.exec <<-SQL
    ALTER TABLE outbox_events ADD CONSTRAINT spec_reject_identity_key_events
    CHECK (event_type NOT LIKE 'identity.%' AND event_type NOT LIKE 'api_key.%')
  SQL
end

private def atomic_event_count : Int64
  TestDatabase.database.scalar("SELECT COUNT(*) FROM outbox_events").as(Int64)
end

describe "Identity and API key mutation outbox atomicity" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
  end

  after_each do
    TestDatabase.database.exec "ALTER TABLE outbox_events DROP CONSTRAINT IF EXISTS spec_reject_identity_key_events"
    TestDatabase.database.exec "ALTER TABLE user_sessions DROP CONSTRAINT IF EXISTS spec_reject_session_insert"
  end

  it "rolls back registration user and session when the event insert fails" do
    reject_identity_key_events!
    expect_raises(::PQ::PQError, /spec_reject_identity_key_events/) { atomic_auth_service.register("New", "new@example.com", "OldPass1!", nil, nil) }
    TestDatabase.database.scalar("SELECT COUNT(*) FROM users").as(Int64).should eq 0
    TestDatabase.database.scalar("SELECT COUNT(*) FROM user_sessions").as(Int64).should eq 0
    atomic_event_count.should eq 0
  end

  it "rolls back registration if the session write fails before the event" do
    TestDatabase.database.exec "ALTER TABLE user_sessions ADD CONSTRAINT spec_reject_session_insert CHECK (user_id = 'never')"
    expect_raises(::PQ::PQError, /spec_reject_session_insert/) { atomic_auth_service.register("New", "new@example.com", "OldPass1!", nil, nil) }
    TestDatabase.database.scalar("SELECT COUNT(*) FROM users").as(Int64).should eq 0
    atomic_event_count.should eq 0
  end

  it "restores login timestamps and session count when the event insert fails" do
    seed_atomic_identity
    timestamp = TestDatabase.database.scalar("SELECT updated_at FROM users WHERE id = 'usr_atomic'").as(Time)
    reject_identity_key_events!
    expect_raises(::PQ::PQError, /spec_reject_identity_key_events/) { atomic_auth_service.login("atomic@example.com", "OldPass1!", nil, nil) }
    TestDatabase.database.scalar("SELECT COUNT(*) FROM user_sessions").as(Int64).should eq 1
    TestDatabase.database.scalar("SELECT last_login_at IS NULL FROM users WHERE id = 'usr_atomic'").as(Bool).should be_true
    TestDatabase.database.scalar("SELECT updated_at FROM users WHERE id = 'usr_atomic'").as(Time).should eq timestamp
    atomic_event_count.should eq 0
  end

  it "keeps the session active when its revocation event fails" do
    tokens = seed_atomic_identity
    reject_identity_key_events!
    expect_raises(::PQ::PQError, /spec_reject_identity_key_events/) { atomic_auth_service.logout(tokens.access_token) }
    TestDatabase.database.scalar("SELECT revoked_at IS NULL FROM user_sessions WHERE id = 'ses_atomic'").as(Bool).should be_true
    atomic_auth_service.authenticate_access_token(tokens.access_token).user_id.should eq "usr_atomic"
    atomic_event_count.should eq 0
  end

  it "keeps all sessions active when logout-all event fails" do
    tokens = seed_atomic_identity
    KemalcrStarter::Infrastructure::DB::UserSessionRepository.new(TestDatabase.database).create("ses_other", "usr_atomic", "fam_other", "other", Time.utc + 1.day)
    reject_identity_key_events!
    expect_raises(::PQ::PQError, /spec_reject_identity_key_events/) { atomic_auth_service.logout_all(tokens.access_token) }
    TestDatabase.database.scalar("SELECT COUNT(*) FROM user_sessions WHERE revoked_at IS NULL").as(Int64).should eq 2
    atomic_event_count.should eq 0
  end

  it "restores password, reset tokens and sessions when reset event fails" do
    tokens = seed_atomic_identity
    seed_atomic_reset_token
    original = TestDatabase.database.scalar("SELECT password_digest FROM users WHERE id = 'usr_atomic'").as(String)
    timestamp = TestDatabase.database.scalar("SELECT updated_at FROM users WHERE id = 'usr_atomic'").as(Time)
    reject_identity_key_events!
    expect_raises(::PQ::PQError, /spec_reject_identity_key_events/) { KemalcrStarter::App.password_reset_service.confirm_reset("reset-atomic", "NewPass1!") }
    TestDatabase.database.scalar("SELECT password_digest FROM users WHERE id = 'usr_atomic'").as(String).should eq original
    TestDatabase.database.scalar("SELECT updated_at FROM users WHERE id = 'usr_atomic'").as(Time).should eq timestamp
    TestDatabase.database.scalar("SELECT COUNT(*) FROM password_reset_tokens WHERE used_at IS NULL").as(Int64).should eq 2
    TestDatabase.database.scalar("SELECT COUNT(*) FROM user_sessions WHERE revoked_at IS NULL").as(Int64).should eq 2
    atomic_auth_service.authenticate_access_token(tokens.access_token).user_id.should eq "usr_atomic"
    atomic_event_count.should eq 0
  end

  it "rolls back API key creation when its event fails" do
    seed_atomic_key
    reject_identity_key_events!
    expect_raises(::PQ::PQError, /spec_reject_identity_key_events/) { atomic_key_service.create_for_actor("usr_atomic", "org_atomic", "New") }
    TestDatabase.database.scalar("SELECT COUNT(*) FROM api_keys").as(Int64).should eq 1
    atomic_event_count.should eq 0
  end

  it "keeps an API key usable when its revocation event fails" do
    secret = seed_atomic_key
    reject_identity_key_events!
    expect_raises(::PQ::PQError, /spec_reject_identity_key_events/) { atomic_key_service.revoke_for_actor("usr_atomic", "org_atomic", "key_atomic") }
    TestDatabase.database.scalar("SELECT revoked_at IS NULL FROM api_keys WHERE id = 'key_atomic'").as(Bool).should be_true
    atomic_key_service.authenticate(secret).api_key_id.should eq "key_atomic"
    atomic_event_count.should eq 0
  end

  it "persists default identity events with their existing payloads and aggregate IDs" do
    service = atomic_auth_service(with_repository: false)
    registered = service.register("New", " NEW@example.com ", "OldPass1!", nil, nil)
    user_id = service.authenticate_access_token(registered.access_token).user_id
    logged_in = service.login("new@example.com", "OldPass1!", nil, nil)
    session_id = service.authenticate_access_token(logged_in.access_token).session_id
    service.logout(logged_in.access_token)
    service.logout_all(registered.access_token)
    events = TestDatabase.database.query_all("SELECT event_type, aggregate_id, event_data::text, status FROM outbox_events ORDER BY event_type", as: {String, String, String, String})
    events.map(&.[0]).should eq ["identity.session.revoked", "identity.user.created", "identity.user.logged_in", "identity.user.logged_out"]
    events.each do |event|
      event[1].should eq user_id
      event[3].should eq "pending"
      event[2].should_not contain("OldPass1!")
      event[2].should_not contain(registered.access_token)
      event[2].should_not contain(registered.refresh_token)
      event[2].should_not contain(logged_in.access_token)
      event[2].should_not contain(logged_in.refresh_token)
    end
    JSON.parse(events[0][2])["session_id"].as_s.should eq session_id
    JSON.parse(events[1][2])["email"].as_s.should eq "new@example.com"
    TestDatabase.database.scalar("SELECT COUNT(*) FROM user_sessions WHERE revoked_at IS NULL").as(Int64).should eq 0
  end

  it "persists API key events through actual App wiring without exposing secrets" do
    seed_atomic_key
    service = KemalcrStarter::App.api_key_service
    created = service.create_for_actor("usr_atomic", "org_atomic", " New ")
    service.authenticate(created[:secret]).api_key_id.should eq created[:id]
    service.revoke_for_actor("usr_atomic", "org_atomic", created[:id])
    expect_raises(KemalcrStarter::Core::Errors::UnauthorizedError) { service.authenticate(created[:secret]) }
    events = TestDatabase.database.query_all("SELECT event_type, aggregate_id, event_data::text, status FROM outbox_events ORDER BY event_type", as: {String, String, String, String})
    events.map(&.[0]).should eq ["api_key.created", "api_key.revoked"]
    events.each do |event|
      event[1].should eq created[:id]
      event[3].should eq "pending"
      JSON.parse(event[2])["organization_id"].as_s.should eq "org_atomic"
      event[2].should_not contain(created[:secret])
      JSON.parse(event[2]).as_h.has_key?("secret_hash").should be_false
    end
    JSON.parse(events[0][2])["name"].as_s.should eq "New"
  end

  it "commits default password reset with its pending event" do
    seed_atomic_identity
    seed_atomic_reset_token
    service = KemalcrStarter::Modules::Identity::PasswordResetService.new(KemalcrStarter::App.settings, TestDatabase.database, KemalcrStarter::Infrastructure::Email::ConsoleEmailAdapter.new)
    service.confirm_reset("reset-atomic", "NewPass1!")
    digest = TestDatabase.database.scalar("SELECT password_digest FROM users WHERE id = 'usr_atomic'").as(String)
    atomic_auth_service.password_hasher.verify("NewPass1!", digest).should be_true
    TestDatabase.database.scalar("SELECT COUNT(*) FROM password_reset_tokens WHERE used_at IS NULL").as(Int64).should eq 0
    TestDatabase.database.scalar("SELECT COUNT(*) FROM user_sessions WHERE revoked_at IS NULL").as(Int64).should eq 0
    atomic_event_count.should eq 1
    event = TestDatabase.database.query_one("SELECT event_type, aggregate_id, event_data::text, status FROM outbox_events", as: {String, String, String, String})
    event[0].should eq "identity.user.password_reset"
    event[1].should eq "usr_atomic"
    JSON.parse(event[2])["email"].as_s.should eq "atomic@example.com"
    event[3].should eq "pending"
    event[2].should_not contain("reset-atomic")
    event[2].should_not contain("NewPass1!")
    expect_raises(KemalcrStarter::Core::Errors::UnauthorizedError) { service.confirm_reset("reset-atomic", "OtherPass1!") }
    atomic_event_count.should eq 1
  end

  it "persists API key events when its optional repository is omitted" do
    seed_atomic_key
    rbac = KemalcrStarter::Core::Rbac::AuthorizationService.new(KemalcrStarter::Infrastructure::DB::RbacRepository.new(TestDatabase.database))
    service = KemalcrStarter::Modules::ApiKeys::ApiKeyService.new(KemalcrStarter::App.settings, TestDatabase.database, rbac_service: rbac)
    created = service.create_for_actor("usr_atomic", "org_atomic", "Default")
    service.revoke_for_actor("usr_atomic", "org_atomic", created[:id])
    TestDatabase.database.query_all("SELECT event_type FROM outbox_events ORDER BY event_type", as: String).should eq ["api_key.created", "api_key.revoked"]
  end

  it "does not emit events on invalid credentials, input or denied API key actions" do
    seed_atomic_key
    expect_raises(KemalcrStarter::Core::Errors::UnauthorizedError) { atomic_auth_service.login("atomic@example.com", "WrongPass1!", nil, nil) }
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { atomic_auth_service.register("New", "new@example.com", "short", nil, nil) }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { atomic_key_service.create_for_actor("missing", "org_atomic", "New") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { atomic_key_service.revoke_for_actor("usr_atomic", "org_other", "key_atomic") }
    expect_raises(KemalcrStarter::Core::Errors::ForbiddenError) { atomic_key_service.revoke_for_actor("usr_atomic", "org_atomic", "missing") }
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { atomic_key_service.create_for_actor("usr_atomic", "org_atomic", " ") }
    atomic_event_count.should eq 0
  end
end
