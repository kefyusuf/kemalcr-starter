require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "digest/sha256"
require "json"

private def idempotency_headers(token : String, key : String) : HTTP::Headers
  headers = HTTP::Headers{
    "Content-Type"    => "application/json",
    "Authorization"   => "Bearer #{token}",
    "Idempotency-Key" => key,
  }

  headers
end

private def json_headers : HTTP::Headers
  HTTP::Headers{"Content-Type" => "application/json"}
end

private def seed_idempotency_org_fixtures(password : String = "supersecret") : Nil
  settings = KemalcrStarter::App.settings
  user_repository = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  organization_repository = KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
  membership_repository = KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)

  user_repository.create("usr_org_001", "orgs@example.com", "Owner", hasher.hash(password))
  organization_repository.create("org_list_001", "acme", "Acme Inc.", "usr_org_001")
  membership_repository.create("mem_org_001", "org_list_001", "usr_org_001", "owner")
end

private def login_for_idempotency_organizations : JSON::Any
  post "/v1/auth/login", headers: json_headers, body: {
    email:    "orgs@example.com",
    password: "supersecret",
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

private def organization_idempotency_scope(actor_id : String) : String
  "#{actor_id}:POST:/v1/organizations"
end

private def organization_idempotency_fingerprint(actor_id : String, request_body : String) : String
  normalized_body = JSON.parse(request_body).to_json
  Digest::SHA256.hexdigest(["POST", "/v1/organizations", actor_id, normalized_body].join(":"))
end

describe "Organization create idempotency" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_idempotency_org_fixtures
  end

  it "replays the previous response for the same key and payload" do
    login_response = login_for_idempotency_organizations
    access_token = login_response["access_token"].as_s
    request_body = {slug: "initech", name: "Initech"}.to_json

    post "/v1/organizations", headers: idempotency_headers(access_token, "org-create-1"), body: request_body

    response.status_code.should eq 201
    first = JSON.parse(response.body)

    post "/v1/organizations", headers: idempotency_headers(access_token, "org-create-1"), body: request_body

    response.status_code.should eq 201
    replay = JSON.parse(response.body)
    replay["id"].as_s.should eq first["id"].as_s

    organizations = KemalcrStarter::Infrastructure::DB::OrganizationRepository
      .new(TestDatabase.database)
      .list_active_for_user("usr_org_001")

    organizations.size.should eq 2
  end

  it "returns conflict for the same key with a different payload" do
    login_response = login_for_idempotency_organizations
    access_token = login_response["access_token"].as_s

    post "/v1/organizations", headers: idempotency_headers(access_token, "org-create-2"), body: {
      slug: "initech",
      name: "Initech",
    }.to_json

    response.status_code.should eq 201

    post "/v1/organizations", headers: idempotency_headers(access_token, "org-create-2"), body: {
      slug: "initech-2",
      name: "Initech Two",
    }.to_json

    response.status_code.should eq 409
  end

  it "returns conflict while the request is already in progress" do
    login_response = login_for_idempotency_organizations
    access_token = login_response["access_token"].as_s
    request_body = {slug: "initech", name: "Initech"}.to_json

    KemalcrStarter::Infrastructure::DB::IdempotencyKeyRepository
      .new(TestDatabase.database)
      .create(
        "idem_inflight_001",
        organization_idempotency_scope("usr_org_001"),
        "org-create-3",
        organization_idempotency_fingerprint("usr_org_001", request_body),
        Time.utc + 30.seconds
      )

    post "/v1/organizations", headers: idempotency_headers(access_token, "org-create-3"), body: request_body

    response.status_code.should eq 409
  end
end
