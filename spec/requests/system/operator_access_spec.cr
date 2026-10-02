require "../../spec_helper"
require "../../support/db/test_database"

private def operator_request(method : String, path : String, headers = HTTP::Headers.new) : Nil
  case method
  when "GET"    then get path, headers: headers
  when "POST"   then post path, headers: headers
  when "DELETE" then delete path, headers: headers
  end
end

private def operator_test_configuration(token : String?) : Nil
  if token
    ENV["OPERATOR_TOKEN"] = token
  else
    ENV.delete("OPERATOR_TOKEN")
  end
  Kemal.config.clear
  Kemal.config.env = "test"
  KemalcrStarter::App.reset_services
  KemalcrStarter::App.configure
  Kemal.config.setup
end

private def operator_tenant_headers : HTTP::Headers
  app = KemalcrStarter::App
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(app.settings.password_pepper, 4)
  KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    .create("usr_operator_test", "operator-test@example.com", "Tenant owner", hasher.hash("supersecret"))
  app.organization_service.create_for_actor("usr_operator_test", "operator-test", "Tenant")
  tokens = app.auth_service.login("operator-test@example.com", "supersecret", nil, nil)
  HTTP::Headers{"Authorization" => "Bearer #{tokens.access_token}"}
end

describe "Platform operator access" do
  previous_token = ENV["OPERATOR_TOKEN"]?
  routes = [
    {"GET", "/events/metrics"},
    {"GET", "/events/dead-letter"},
    {"POST", "/events/dead-letter/00000000-0000-0000-0000-000000000000/requeue"},
    {"GET", "/rbac/permissions"},
    {"GET", "/rbac/roles"},
    {"POST", "/rbac/roles/seed"},
    {"DELETE", "/rbac/roles/owner/permissions/organization:delete"},
  ]

  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    operator_test_configuration("spec-only-operator-secret")
  end

  after_each do
    if previous_token
      ENV["OPERATOR_TOKEN"] = previous_token
    else
      ENV.delete("OPERATOR_TOKEN")
    end
  end

  routes.each do |method, path|
    it "rejects anonymous #{method} #{path}" do
      operator_request(method, path)
      response.status_code.should eq 401
      body = JSON.parse(response.body)
      body["error"]["code"].as_s.should eq "AUTH_UNAUTHORIZED"
      body["error"]["request_id"].as_s.should eq response.headers["X-Request-Id"]
    end
  end

  it "does not grant a tenant owner platform access" do
    headers = operator_tenant_headers
    routes.each do |method, path|
      operator_request(method, path, headers)
      response.status_code.should eq 401
    end
  end

  it "preserves global permissions when a tenant owner tries to remove one" do
    headers = operator_tenant_headers
    KemalcrStarter::App.rbac_service.seed_default_roles!
    delete "/rbac/roles/owner/permissions/organization:delete", headers: headers
    response.status_code.should eq 401
    repo = KemalcrStarter::Infrastructure::DB::RbacRepository.new(TestDatabase.database)
    repo.role_has_permission?("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationDelete).should be_true
  end

  it "does not seed global roles for a tenant owner" do
    headers = operator_tenant_headers
    post "/rbac/roles/seed", headers: headers
    response.status_code.should eq 401
    TestDatabase.database.scalar("SELECT COUNT(*) FROM rbac_role_permissions").as(Int64).should eq 0
  end

  it "does not grant a valid tenant API key platform access" do
    operator_tenant_headers
    org_id = TestDatabase.database.scalar("SELECT id FROM organizations LIMIT 1").as(String)
    hasher = KemalcrStarter::Infrastructure::Crypto::ApiKeySecretHasher.new(KemalcrStarter::App.settings.password_pepper)
    secret = hasher.generate_secret
    KemalcrStarter::Infrastructure::DB::ApiKeyRepository.new(TestDatabase.database)
      .create("key_operator_test", org_id, "Tenant key", hasher.prefix(secret), hasher.hash(secret))
    headers = HTTP::Headers{"X-API-Key" => secret}
    routes.each do |method, path|
      operator_request(method, path, headers)
      response.status_code.should eq 401
    end
  end

  it "preserves a dead letter when a tenant owner tries to requeue it" do
    headers = operator_tenant_headers
    repo = KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
    event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("another-tenant")
    repo.create(event)
    repo.move_to_dead_letter(event.event_id, "private-failure")
    id = repo.list_dead_letters.first.id
    post "/events/dead-letter/#{id}/requeue", headers: headers
    response.status_code.should eq 401
    repo.list_dead_letters.map(&.id).should eq [id]
    repo.find(event.event_id).not_nil!.status.should eq "dead_letter"
    TestDatabase.database.scalar("SELECT COUNT(*) FROM outbox_events WHERE aggregate_id = 'another-tenant'").as(Int64).should eq 1
  end

  it "rejects incorrect operator credentials on every protected route" do
    routes.each do |method, path|
      operator_request(method, path, HTTP::Headers{"X-Operator-Token" => "wrong-secret"})
      response.status_code.should eq 401
    end
  end

  it "disables operator access when no token is configured" do
    operator_test_configuration(nil)
    routes.each do |method, path|
      operator_request(method, path, HTTP::Headers{"X-Operator-Token" => "spec-only-operator-secret"})
      response.status_code.should eq 401
    end
  end

  it "disables operator access for whitespace configuration and credentials" do
    operator_test_configuration("   ")
    get "/events/metrics", headers: HTTP::Headers{"X-Operator-Token" => "   "}
    response.status_code.should eq 401
  end

  it "allows an operator to inspect metrics and global roles without a tenant session" do
    headers = HTTP::Headers{"X-Operator-Token" => "spec-only-operator-secret"}
    ["/events/metrics", "/events/dead-letter", "/rbac/permissions", "/rbac/roles"].each do |path|
      get path, headers: headers
      response.status_code.should eq 200
    end
  end

  it "allows an operator to seed and remove global permissions" do
    headers = HTTP::Headers{"X-Operator-Token" => "spec-only-operator-secret"}
    post "/rbac/roles/seed", headers: headers
    response.status_code.should eq 200
    repo = KemalcrStarter::Infrastructure::DB::RbacRepository.new(TestDatabase.database)
    repo.role_has_permission?("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationDelete).should be_true
    delete "/rbac/roles/owner/permissions/organization:delete", headers: headers
    response.status_code.should eq 200
    repo.role_has_permission?("owner", KemalcrStarter::Core::Rbac::Permission::OrganizationDelete).should be_false
  end

  it "allows an operator to requeue a persisted dead letter" do
    repo = KemalcrStarter::Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
    event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("another-tenant")
    repo.create(event)
    repo.move_to_dead_letter(event.event_id, "private-failure")
    id = repo.list_dead_letters.first.id
    post "/events/dead-letter/#{id}/requeue", headers: HTTP::Headers{"X-Operator-Token" => "spec-only-operator-secret"}
    response.status_code.should eq 200
    repo.list_dead_letters.should be_empty
    TestDatabase.database.scalar("SELECT COUNT(*) FROM outbox_events WHERE status = 'pending'").as(Int64).should eq 1
  end

  it "keeps public health and contract endpoints accessible with operator access disabled" do
    operator_test_configuration(nil)
    ["/health", "/version", "/openapi"].each do |path|
      get path
      response.status_code.should eq 200
    end
  end
end
