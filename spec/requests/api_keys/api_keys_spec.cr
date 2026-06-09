require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "json"

private def api_keys_json_headers(token : String? = nil, idempotency_key : String? = nil) : HTTP::Headers
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Authorization"] = "Bearer #{token}" if token
  headers["Idempotency-Key"] = idempotency_key if idempotency_key
  headers
end

private def seed_api_key_fixtures(password : String = "supersecret") : Nil
  settings = KemalcrStarter::App.settings
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)

  user_repository.create("usr_api_001", "owner@example.com", "Owner", hasher.hash(password))
  user_repository.create("usr_api_002", "member@example.com", "Member", hasher.hash(password))
  organization_repository.create("org_api_001", "acme", "Acme Inc.", "usr_api_001")
  membership_repository.create("mem_api_001", "org_api_001", "usr_api_001", "owner")
  membership_repository.create("mem_api_002", "org_api_001", "usr_api_002", "member")
end

private def login_for_api_keys(email : String, password : String = "supersecret") : JSON::Any
  post "/v1/auth/login", headers: api_keys_json_headers, body: {
    email:    email,
    password: password,
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

describe "API key endpoints" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_api_key_fixtures
  end

  it "creates an API key and reveals the secret only in the create response" do
    login_response = login_for_api_keys("owner@example.com")
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_api_001/api-keys", headers: api_keys_json_headers(access_token, "api-key-create-1"), body: {
      name: "deploy-bot",
    }.to_json

    response.status_code.should eq 201
    created = JSON.parse(response.body)
    created["name"].as_s.should eq "deploy-bot"
    created["secret"].as_s.should start_with("kma_")
    created_id = created["id"].as_s

    get "/v1/organizations/org_api_001/api-keys", headers: api_keys_json_headers(access_token)

    response.status_code.should eq 200
    body = JSON.parse(response.body)
    api_keys = body["data"].as_a
    api_keys.size.should eq 1
    api_keys.first["id"].as_s.should eq created_id
    api_keys.first.as_h["secret"]?.should be_nil
  end

  it "rejects API key creation for non-manager members" do
    login_response = login_for_api_keys("member@example.com")
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_api_001/api-keys", headers: api_keys_json_headers(access_token), body: {
      name: "member-bot",
    }.to_json

    response.status_code.should eq 403
  end

  it "revokes an API key and removes it from the active list" do
    login_response = login_for_api_keys("owner@example.com")
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_api_001/api-keys", headers: api_keys_json_headers(access_token), body: {
      name: "deploy-bot",
    }.to_json

    response.status_code.should eq 201
    api_key_id = JSON.parse(response.body)["id"].as_s

    delete "/v1/organizations/org_api_001/api-keys/#{api_key_id}", headers: api_keys_json_headers(access_token)

    response.status_code.should eq 204

    get "/v1/organizations/org_api_001/api-keys", headers: api_keys_json_headers(access_token)

    response.status_code.should eq 200
    JSON.parse(response.body)["data"].as_a.size.should eq 0
  end
end
