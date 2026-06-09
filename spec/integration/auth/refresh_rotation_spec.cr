require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "json"

private def integration_json_headers(authorization : String? = nil) : HTTP::Headers
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Authorization"] = "Bearer #{authorization}" if authorization
  headers
end

private def seed_integration_user(password : String = "supersecret") : Nil
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(
    KemalcrStarter::App.settings.password_pepper,
    KemalcrStarter::App.settings.password_hash_cost
  )

  KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    .create("usr_auth_001", "auth@example.com", "Auth", hasher.hash(password))
end

private def login_tokens(email : String = "auth@example.com", password : String = "supersecret") : JSON::Any
  post "/v1/auth/login", headers: integration_json_headers, body: {
    email:    email,
    password: password,
  }.to_json

  response.status_code.should eq 200
  JSON.parse(response.body)
end

describe "Authentication integration flows" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_integration_user
  end

  it "rotates refresh tokens" do
    login_response = login_tokens
    refresh_token = login_response["refresh_token"].as_s

    post "/v1/auth/refresh", headers: integration_json_headers, body: {
      refresh_token: refresh_token,
    }.to_json

    response.status_code.should eq 200

    refreshed = JSON.parse(response.body)
    refreshed["refresh_token"].as_s.should_not eq refresh_token
  end

  it "revokes the token family when a rotated refresh token is reused" do
    login_response = login_tokens
    original_refresh_token = login_response["refresh_token"].as_s

    post "/v1/auth/refresh", headers: integration_json_headers, body: {
      refresh_token: original_refresh_token,
    }.to_json

    response.status_code.should eq 200
    rotated_refresh_token = JSON.parse(response.body)["refresh_token"].as_s

    post "/v1/auth/refresh", headers: integration_json_headers, body: {
      refresh_token: original_refresh_token,
    }.to_json

    response.status_code.should eq 409

    reused = JSON.parse(response.body)
    reused["error"]["code"].as_s.should eq "REQUEST_CONFLICT"

    post "/v1/auth/refresh", headers: integration_json_headers, body: {
      refresh_token: rotated_refresh_token,
    }.to_json

    response.status_code.should eq 409
  end

  it "invalidates the current refresh path on logout" do
    login_response = login_tokens
    access_token = login_response["access_token"].as_s
    refresh_token = login_response["refresh_token"].as_s

    post "/v1/auth/logout", headers: integration_json_headers(access_token)

    response.status_code.should eq 200

    post "/v1/auth/refresh", headers: integration_json_headers, body: {
      refresh_token: refresh_token,
    }.to_json

    response.status_code.should eq 409
  end

  it "invalidates every active session on logout-all" do
    first_login = login_tokens
    second_login = login_tokens

    post "/v1/auth/logout-all", headers: integration_json_headers(first_login["access_token"].as_s)

    response.status_code.should eq 200

    post "/v1/auth/refresh", headers: integration_json_headers, body: {
      refresh_token: second_login["refresh_token"].as_s,
    }.to_json

    response.status_code.should eq 409
  end
end
