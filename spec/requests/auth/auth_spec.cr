require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/redis/test_redis"
require "json"

private def auth_json_headers(authorization : String? = nil) : HTTP::Headers
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Authorization"] = "Bearer #{authorization}" if authorization
  headers
end

private class RejectingAuthThrottle < KemalcrStarter::Modules::Identity::AuthThrottle
  def initialize(@blocked_endpoint : String)
  end

  def check!(context : KemalcrStarter::Modules::Identity::AuthThrottleContext) : Nil
    return unless context.endpoint == @blocked_endpoint

    raise KemalcrStarter::Core::Errors::TooManyRequestsError.new
  end
end

private def install_redis_auth_throttle(login_limit : Int32, refresh_limit : Int32, window_seconds : Int32 = 60) : Nil
  KemalcrStarter::App.install_auth_throttle(
    KemalcrStarter::Modules::Identity::RedisAuthThrottle.new(
      redis_url: KemalcrStarter::App.settings.redis_url,
      login_limit: login_limit,
      refresh_limit: refresh_limit,
      register_limit: login_limit,
      window_seconds: window_seconds
    )
  )
end

private def seed_auth_user(password : String = "supersecret") : Nil
  hasher = KemalcrStarter::Infrastructure::Crypto::PasswordHasher.new(
    KemalcrStarter::App.settings.password_pepper,
    KemalcrStarter::App.settings.password_hash_cost
  )

  KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
    .create("usr_auth_001", "auth@example.com", "Auth", hasher.hash(password))
end

describe "Authentication request endpoints" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    TestRedis.clear!
    seed_auth_user
  end

  it "logs in with valid credentials" do
    post "/v1/auth/login", headers: auth_json_headers, body: {
      email:    "auth@example.com",
      password: "supersecret",
    }.to_json

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    body["token_type"].as_s.should eq "Bearer"
    body["expires_in"].as_i.should be > 0
    body["access_token"].as_s.should contain "."
    body["refresh_token"].as_s.should contain "."
  end

  it "rejects invalid credentials" do
    post "/v1/auth/login", headers: auth_json_headers, body: {
      email:    "auth@example.com",
      password: "wrong-password",
    }.to_json

    response.status_code.should eq 401

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "AUTH_UNAUTHORIZED"
  end

  it "allows the auth throttle hook to reject login" do
    KemalcrStarter::App.install_auth_throttle(RejectingAuthThrottle.new("/v1/auth/login"))

    post "/v1/auth/login", headers: auth_json_headers, body: {
      email:    "auth@example.com",
      password: "supersecret",
    }.to_json

    response.status_code.should eq 429

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "RATE_LIMITED"
  end

  it "allows the auth throttle hook to reject refresh" do
    post "/v1/auth/login", headers: auth_json_headers, body: {
      email:    "auth@example.com",
      password: "supersecret",
    }.to_json

    refresh_token = JSON.parse(response.body)["refresh_token"].as_s
    KemalcrStarter::App.install_auth_throttle(RejectingAuthThrottle.new("/v1/auth/refresh"))

    post "/v1/auth/refresh", headers: auth_json_headers, body: {
      refresh_token: refresh_token,
    }.to_json

    response.status_code.should eq 429

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "RATE_LIMITED"
  end

  it "throttles repeated login attempts within the configured window" do
    install_redis_auth_throttle(login_limit: 2, refresh_limit: 10)

    2.times do
      post "/v1/auth/login", headers: auth_json_headers.tap { |headers| headers["X-Forwarded-For"] = "198.51.100.7" }, body: {
        email:    "auth@example.com",
        password: "wrong-password",
      }.to_json

      response.status_code.should eq 401
    end

    post "/v1/auth/login", headers: auth_json_headers.tap { |headers| headers["X-Forwarded-For"] = "198.51.100.7" }, body: {
      email:    "auth@example.com",
      password: "wrong-password",
    }.to_json

    response.status_code.should eq 429

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "RATE_LIMITED"

    post "/v1/auth/login", headers: auth_json_headers.tap { |headers| headers["X-Forwarded-For"] = "203.0.113.10" }, body: {
      email:    "auth@example.com",
      password: "wrong-password",
    }.to_json

    response.status_code.should eq 401
  end

  it "throttles repeated refresh attempts within the configured window" do
    install_redis_auth_throttle(login_limit: 10, refresh_limit: 1)

    post "/v1/auth/login", headers: auth_json_headers.tap { |headers| headers["X-Forwarded-For"] = "198.51.100.8" }, body: {
      email:    "auth@example.com",
      password: "supersecret",
    }.to_json

    login_body = JSON.parse(response.body)
    first_refresh_token = login_body["refresh_token"].as_s

    post "/v1/auth/refresh", headers: auth_json_headers.tap { |headers| headers["X-Forwarded-For"] = "198.51.100.8" }, body: {
      refresh_token: first_refresh_token,
    }.to_json

    response.status_code.should eq 200

    next_refresh_token = JSON.parse(response.body)["refresh_token"].as_s

    post "/v1/auth/refresh", headers: auth_json_headers.tap { |headers| headers["X-Forwarded-For"] = "198.51.100.8" }, body: {
      refresh_token: next_refresh_token,
    }.to_json

    response.status_code.should eq 429

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "RATE_LIMITED"
  end
end
