require "../../spec_helper"
require "json"

get "/__test/api-error" do
  raise KemalcrStarter::Core::Errors::UnauthorizedError.new
end

get "/__test/internal-error" do
  raise "boom"
end

describe "System endpoints" do
  it "returns health payload with request metadata" do
    get "/health"

    response.status_code.should eq 200
    response.headers["X-Request-Id"]?.should_not be_nil
    response.headers["X-Content-Type-Options"].should eq "nosniff"

    body = JSON.parse(response.body)
    body["status"].as_s.should eq "ok"
    body["request_id"].as_s.should eq response.headers["X-Request-Id"]
  end

  it "propagates incoming request ids" do
    get "/health", headers: HTTP::Headers{"X-Request-Id" => "req_spec_123"}

    response.status_code.should eq 200
    response.headers["X-Request-Id"].should eq "req_spec_123"

    body = JSON.parse(response.body)
    body["request_id"].as_s.should eq "req_spec_123"
  end

  it "returns version metadata" do
    get "/version"

    response.status_code.should eq 200

    body = JSON.parse(response.body)
    body["service"].as_s.should eq "kemalcr_starter"
    body["version"].as_s.should eq "0.1.0"
    body["build_time"].as_s.should eq "unknown"
    body["git_sha"].as_s.should eq "unknown"
    body["request_id"].as_s.should eq response.headers["X-Request-Id"]
  end

  it "serves the OpenAPI document" do
    get "/openapi"

    response.status_code.should eq 200
    response.content_type.should eq "application/yaml"
    response.body.should contain "openapi: 3.1.0"
  end
end

describe "Error handling" do
  it "renders api errors using the standard envelope" do
    get "/__test/api-error"

    response.status_code.should eq 401
    response.headers["X-Request-Id"]?.should_not be_nil

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "AUTH_UNAUTHORIZED"
    body["error"]["request_id"].as_s.should eq response.headers["X-Request-Id"]
  end

  it "renders unknown errors using the internal server envelope" do
    get "/__test/internal-error"

    response.status_code.should eq 500

    body = JSON.parse(response.body)
    body["error"]["code"].as_s.should eq "INTERNAL_SERVER_ERROR"
  end
end
