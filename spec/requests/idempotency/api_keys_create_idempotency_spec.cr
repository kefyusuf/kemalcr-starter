require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "digest/sha256"
require "json"

private def api_key_idempotency_headers(token : String, key : String) : HTTP::Headers
  HTTP::Headers{
    "Content-Type"    => "application/json",
    "Authorization"   => "Bearer #{token}",
    "Idempotency-Key" => key,
  }
end

private def api_key_plain_headers : HTTP::Headers
  HTTP::Headers{"Content-Type" => "application/json"}
end

private def seed_api_key_idempotency_fixtures(password : String = "supersecret") : Nil
  settings = KemalcrStarter::App.settings
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)

  user_repository.create("usr_api_001", "owner@example.com", "Owner", hasher.hash(password))
  organization_repository.create("org_api_001", "acme", "Acme Inc.", "usr_api_001")
  membership_repository.create("mem_api_001", "org_api_001", "usr_api_001", "owner")
end

private def login_for_api_key_idempotency : JSON::Any
  post "/v1/auth/login", headers: api_key_plain_headers, body: {
    email:    "owner@example.com",
    password: "supersecret",
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

private def api_key_idempotency_scope(actor_id : String) : String
  "#{actor_id}:POST:/v1/organizations/:organization_id/api-keys"
end

private def api_key_idempotency_fingerprint(actor_id : String, request_body : String) : String
  normalized_body = JSON.parse(request_body).to_json
  Digest::SHA256.hexdigest(["POST", "/v1/organizations/:organization_id/api-keys", actor_id, normalized_body].join(":"))
end

describe "API key create idempotency" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_api_key_idempotency_fixtures
  end

  it "replays the previous API key response for the same key and payload" do
    login_response = login_for_api_key_idempotency
    access_token = login_response["access_token"].as_s
    request_body = {name: "deploy-bot"}.to_json

    post "/v1/organizations/org_api_001/api-keys", headers: api_key_idempotency_headers(access_token, "api-key-create-1"), body: request_body

    response.status_code.should eq 201
    first = JSON.parse(response.body)

    post "/v1/organizations/org_api_001/api-keys", headers: api_key_idempotency_headers(access_token, "api-key-create-1"), body: request_body

    response.status_code.should eq 201
    replay = JSON.parse(response.body)
    replay["id"].as_s.should eq first["id"].as_s
    replay["secret"].as_s.should eq first["secret"].as_s

    api_keys = KemalcrStarter::Infrastructure::DB::ApiKeyRepository
      .new(TestDatabase.database)
      .list_active_for_organization("org_api_001")

    api_keys.size.should eq 1
  end

  it "returns conflict for the same API key idempotency key with a different payload" do
    login_response = login_for_api_key_idempotency
    access_token = login_response["access_token"].as_s

    post "/v1/organizations/org_api_001/api-keys", headers: api_key_idempotency_headers(access_token, "api-key-create-2"), body: {
      name: "deploy-bot",
    }.to_json

    response.status_code.should eq 201

    post "/v1/organizations/org_api_001/api-keys", headers: api_key_idempotency_headers(access_token, "api-key-create-2"), body: {
      name: "ci-bot",
    }.to_json

    response.status_code.should eq 409
  end

  it "returns conflict while the API key request is already in progress" do
    login_response = login_for_api_key_idempotency
    access_token = login_response["access_token"].as_s
    request_body = {name: "deploy-bot"}.to_json

    KemalcrStarter::Infrastructure::DB::IdempotencyKeyRepository
      .new(TestDatabase.database)
      .create(
        "idem_inflight_api_key_001",
        api_key_idempotency_scope("usr_api_001"),
        "api-key-create-3",
        api_key_idempotency_fingerprint("usr_api_001", request_body),
        Time.utc + 30.seconds
      )

    post "/v1/organizations/org_api_001/api-keys", headers: api_key_idempotency_headers(access_token, "api-key-create-3"), body: request_body

    response.status_code.should eq 409
  end
end
