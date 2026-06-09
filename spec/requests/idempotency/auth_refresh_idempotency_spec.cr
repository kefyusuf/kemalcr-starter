require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "digest/sha256"
require "json"

private def auth_idempotency_headers(key : String? = nil) : HTTP::Headers
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Idempotency-Key"] = key if key
  headers
end

private def seed_refresh_idempotency_user(password : String = "supersecret") : Nil
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(
    KemalcrStarter::App.settings.password_pepper,
    KemalcrStarter::App.settings.password_hash_cost
  )

  KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    .create("usr_auth_001", "auth@example.com", "Auth", hasher.hash(password))
end

private def idempotent_login_tokens : JSON::Any
  post "/v1/auth/login", headers: auth_idempotency_headers, body: {
    email:    "auth@example.com",
    password: "supersecret",
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

private def refresh_idempotency_scope(actor_id : String) : String
  "#{actor_id}:POST:/v1/auth/refresh"
end

private def refresh_idempotency_fingerprint(actor_id : String, request_body : String) : String
  normalized_body = JSON.parse(request_body).to_json
  Digest::SHA256.hexdigest(["POST", "/v1/auth/refresh", actor_id, normalized_body].join(":"))
end

describe "Auth refresh idempotency" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_refresh_idempotency_user
  end

  it "replays the previous token pair for the same key and payload" do
    login_response = idempotent_login_tokens
    refresh_token = login_response["refresh_token"].as_s
    request_body = {refresh_token: refresh_token}.to_json

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-1"), body: request_body

    response.status_code.should eq 200
    first = JSON.parse(response.body)

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-1"), body: request_body

    response.status_code.should eq 200
    replay = JSON.parse(response.body)
    replay["refresh_token"].as_s.should eq first["refresh_token"].as_s
    replay["access_token"].as_s.should eq first["access_token"].as_s
  end

  it "returns conflict for the same key with a different payload" do
    first_login = idempotent_login_tokens
    second_login = idempotent_login_tokens

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-2"), body: {
      refresh_token: first_login["refresh_token"].as_s,
    }.to_json

    response.status_code.should eq 200

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-2"), body: {
      refresh_token: second_login["refresh_token"].as_s,
    }.to_json

    response.status_code.should eq 409
  end

  it "returns conflict while the refresh request is already in progress" do
    login_response = idempotent_login_tokens
    refresh_token = login_response["refresh_token"].as_s
    request_body = {refresh_token: refresh_token}.to_json

    KemalcrStarter::Infrastructure::DB::IdempotencyKeyRepository
      .new(TestDatabase.database)
      .create(
        "idem_inflight_auth_refresh_001",
        refresh_idempotency_scope("usr_auth_001"),
        "auth-refresh-3",
        refresh_idempotency_fingerprint("usr_auth_001", request_body),
        Time.utc + 30.seconds
      )

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-3"), body: request_body

    response.status_code.should eq 409
  end

  it "still revokes the token family when the same refresh token is reused with a different key" do
    login_response = idempotent_login_tokens
    original_refresh_token = login_response["refresh_token"].as_s

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-4a"), body: {
      refresh_token: original_refresh_token,
    }.to_json

    response.status_code.should eq 200
    rotated_refresh_token = JSON.parse(response.body)["refresh_token"].as_s

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-4b"), body: {
      refresh_token: original_refresh_token,
    }.to_json

    response.status_code.should eq 409

    post "/v1/auth/refresh", headers: auth_idempotency_headers("auth-refresh-4c"), body: {
      refresh_token: rotated_refresh_token,
    }.to_json

    response.status_code.should eq 409
  end
end
