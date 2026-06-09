require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "json"

private def api_key_integration_headers(authorization : String? = nil, api_key : String? = nil) : HTTP::Headers
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Authorization"] = "Bearer #{authorization}" if authorization
  headers["X-API-Key"] = api_key if api_key
  headers
end

private def seed_api_key_auth_fixtures(password : String = "supersecret") : Nil
  settings = KemalcrStarter::App.settings
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)

  user_repository.create("usr_api_auth_001", "owner@example.com", "Owner", hasher.hash(password))
  user_repository.create("usr_api_auth_002", "other@example.com", "Other", hasher.hash(password))
  organization_repository.create("org_api_auth_001", "acme", "Acme Inc.", "usr_api_auth_001")
  organization_repository.create("org_api_auth_002", "globex", "Globex", "usr_api_auth_002")
  membership_repository.create("mem_api_auth_001", "org_api_auth_001", "usr_api_auth_001", "owner")
  membership_repository.create("mem_api_auth_002", "org_api_auth_002", "usr_api_auth_002", "owner")
end

private def login_for_api_key_auth : JSON::Any
  post "/v1/auth/login", headers: api_key_integration_headers, body: {
    email:    "owner@example.com",
    password: "supersecret",
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

private def create_api_key_secret(access_token : String) : String
  post "/v1/organizations/org_api_auth_001/api-keys", headers: api_key_integration_headers(access_token), body: {
    name: "machine-reader",
  }.to_json

  response.status_code.should eq 201
  JSON.parse(response.body)["secret"].as_s
end

describe "API key machine authentication" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_api_key_auth_fixtures
  end

  it "allows organization detail access with a valid API key" do
    access_token = login_for_api_key_auth["access_token"].as_s
    secret = create_api_key_secret(access_token)

    get "/v1/organizations/org_api_auth_001", headers: api_key_integration_headers(nil, secret)

    response.status_code.should eq 200
    body = JSON.parse(response.body)
    body["id"].as_s.should eq "org_api_auth_001"
  end

  it "allows organization membership listing with a valid API key in the same organization" do
    access_token = login_for_api_key_auth["access_token"].as_s
    secret = create_api_key_secret(access_token)

    get "/v1/organizations/org_api_auth_001/memberships", headers: api_key_integration_headers(nil, secret)

    response.status_code.should eq 200
    memberships = JSON.parse(response.body)["data"].as_a
    memberships.size.should eq 1
    memberships.first["organization_id"].as_s.should eq "org_api_auth_001"
  end

  it "rejects revoked API keys" do
    access_token = login_for_api_key_auth["access_token"].as_s
    secret = create_api_key_secret(access_token)

    get "/v1/organizations/org_api_auth_001/api-keys", headers: api_key_integration_headers(access_token)
    api_key_id = JSON.parse(response.body)["data"].as_a.first["id"].as_s

    delete "/v1/organizations/org_api_auth_001/api-keys/#{api_key_id}", headers: api_key_integration_headers(access_token)
    response.status_code.should eq 204

    get "/v1/organizations/org_api_auth_001", headers: api_key_integration_headers(nil, secret)

    response.status_code.should eq 401
  end

  it "enforces organization boundaries for machine access" do
    access_token = login_for_api_key_auth["access_token"].as_s
    secret = create_api_key_secret(access_token)

    get "/v1/organizations/org_api_auth_002", headers: api_key_integration_headers(nil, secret)

    response.status_code.should eq 403
  end
end
