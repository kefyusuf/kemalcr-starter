require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "json"

private def me_json_headers(token : String? = nil) : HTTP::Headers
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Authorization"] = "Bearer #{token}" if token
  headers
end

private def seed_me_fixtures(password : String = "supersecret") : Nil
  settings = KemalcrStarter::App.settings
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)
  user_repository.create("usr_me_001", "me@example.com", "Me", hasher.hash(password))

  user_repository.create("usr_other_001", "other@example.com", "Other", hasher.hash(password))
  organization_repository.create("org_me_001", "acme", "Acme Inc.", "usr_me_001")
  organization_repository.create("org_me_002", "globex", "Globex", "usr_other_001")
  organization_repository.create("org_me_003", "initech", "Initech", "usr_other_001")
  membership_repository.create("mem_me_001", "org_me_001", "usr_me_001", "owner")
  membership_repository.create("mem_me_002", "org_me_002", "usr_me_001", "member")
end

private def login_for_me : JSON::Any
  post "/v1/auth/login", headers: me_json_headers, body: {
    email:    "me@example.com",
    password: "supersecret",
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

describe "Current actor endpoint" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_me_fixtures
  end

  it "returns the current user and active organization context" do
    login_response = login_for_me
    access_token = login_response["access_token"].as_s

    get "/v1/me", headers: me_json_headers(access_token)

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    body["user"]["id"].as_s.should eq "usr_me_001"
    body["active_organization"]["id"].as_s.should eq "org_me_001"
    body["membership"]["role"].as_s.should eq "owner"
  end

  it "rejects requests without a bearer token" do
    get "/v1/me"

    response.status_code.should eq 401
  end

  it "switches the active organization and reissues tokens" do
    login_response = login_for_me
    access_token = login_response["access_token"].as_s

    post "/v1/me/active-organization", headers: me_json_headers(access_token), body: {
      organization_id: "org_me_002",
    }.to_json

    response.status_code.should eq 200

    switch_response = JSON.parse(response.body)
    new_access_token = switch_response["access_token"].as_s

    claims = KemalcrStarter::App.auth_service.authenticate_access_token(new_access_token)
    claims.active_organization_id.should eq "org_me_002"

    get "/v1/me", headers: me_json_headers(new_access_token)

    response.status_code.should eq 200
    body = JSON.parse(response.body)
    body["active_organization"]["id"].as_s.should eq "org_me_002"
    body["membership"]["role"].as_s.should eq "member"
  end

  it "rejects switching to an organization without membership" do
    login_response = login_for_me
    access_token = login_response["access_token"].as_s

    post "/v1/me/active-organization", headers: me_json_headers(access_token), body: {
      organization_id: "org_me_003",
    }.to_json

    response.status_code.should eq 403

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "AUTH_FORBIDDEN"
  end
end
