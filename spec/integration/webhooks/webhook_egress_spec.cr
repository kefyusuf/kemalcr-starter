require "../../spec_helper"
require "../../support/db/test_database"
require "../../support/webhook_receiver"

private def seed_egress_tenant : Nil
  users = KemalcrStarter::Infrastructure::DB::UserRepository.new(TestDatabase.database)
  users.create("usr_egress", "egress@example.com", "Egress", "unused")
  KemalcrStarter::Infrastructure::DB::OrganizationRepository.new(TestDatabase.database)
    .create("org_egress", "egress", "Egress", "usr_egress")
  KemalcrStarter::Infrastructure::DB::OrganizationMembershipRepository.new(TestDatabase.database)
    .create("mem_egress", "org_egress", "usr_egress", "owner", joined_at: Time.utc)
end

private class EgressTestResolver < KemalcrStarter::Infrastructure::Http::WebhookResolver
  property addresses : Array(String)

  def initialize(@addresses : Array(String))
  end

  def resolve(host : String, port : Int32) : Array(Socket::IPAddress)
    @addresses.map { |address| Socket::IPAddress.new(address, port) }
  end
end

private def egress_test_settings : KemalcrStarter::Core::Config::Settings
  KemalcrStarter::App.settings.copy_with(webhook_allow_test_loopback: true)
end

private def egress_test_service(settings : KemalcrStarter::Core::Config::Settings, url : String,
                                resolver : KemalcrStarter::Infrastructure::Http::WebhookResolver) : KemalcrStarter::Modules::Webhooks::WebhookService
  KemalcrStarter::Infrastructure::DB::WebhookEndpointRepository.new(TestDatabase.database).create(
    id: "whk_egress_transport", organization_id: "org_egress", url: url,
    secret: "secret", description: nil, event_types: ["organization.updated"], created_by: "usr_egress"
  )
  policy = KemalcrStarter::Infrastructure::Http::WebhookDestination.new(settings, resolver)
  KemalcrStarter::Modules::Webhooks::WebhookService.new(settings, TestDatabase.database, destination: policy)
end

describe "Webhook destination protection" do
  before_each do
    TestDatabase.migrate!
    TestDatabase.truncate_all!
    seed_egress_tenant
  end

  [
    "http://example.com/hooks",
    "https://127.0.0.1/hooks",
    "https://127.1/hooks",
    "https://2130706433/hooks",
    "https://0x7f000001/hooks",
    "https://0177.0.0.1/hooks",
    "https://10.0.0.1/hooks",
    "https://172.16.0.1/hooks",
    "https://192.168.0.1/hooks",
    "https://169.254.169.254/hooks",
    "https://168.63.129.16/hooks",
    "https://100.64.0.1/hooks",
    "https://0.0.0.0/hooks",
    "https://224.0.0.1/hooks",
    "https://192.0.2.1/hooks",
    "https://[::1]/hooks",
    "https://[fc00::1]/hooks",
    "https://[fe80::1]/hooks",
    "https://[::ffff:127.0.0.1]/hooks",
    "https://[2001:db8::1]/hooks",
    "https://[64:ff9b::7f00:1]/hooks",
    "https://localhost/hooks",
    "https://user:password@example.com/hooks",
    "https://example.com/hooks#fragment",
    "https://example.com:8443/hooks",
  ].each do |url|
    it "rejects unsafe registration #{url}" do
      service = KemalcrStarter::Modules::Webhooks::WebhookService.new(KemalcrStarter::App.settings, TestDatabase.database)
      expect_raises(KemalcrStarter::Core::Errors::ValidationError) do
        service.create_endpoint("usr_egress", "org_egress", url, nil, [] of String)
      end
      TestDatabase.database.scalar("SELECT COUNT(*) FROM webhook_endpoints").as(Int64).should eq 0
    end
  end

  it "allows a public HTTPS destination to be registered" do
    service = KemalcrStarter::Modules::Webhooks::WebhookService.new(KemalcrStarter::App.settings, TestDatabase.database)
    created = service.create_endpoint("usr_egress", "org_egress", "https://example.com/hooks?version=1", nil, [] of String)
    created.endpoint.url.should eq "https://example.com/hooks?version=1"
  end

  it "blocks a legacy loopback endpoint before sending any tenant payload" do
    receiver = KemalcrStarter::WebhookReceiver.new("secret")
    port = receiver.start
    KemalcrStarter::Infrastructure::DB::WebhookEndpointRepository.new(TestDatabase.database).create(
      id: "whk_legacy_egress", organization_id: "org_egress", url: "http://127.0.0.1:#{port}/hooks",
      secret: "secret", description: nil, event_types: ["organization.updated"], created_by: "usr_egress"
    )
    service = KemalcrStarter::Modules::Webhooks::WebhookService.new(KemalcrStarter::App.settings, TestDatabase.database)
    event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_egress")
    expect_raises(Exception, /webhook_delivery_failed/) { service.dispatch_event(event) }
    receiver.requests.should be_empty
    deliveries = KemalcrStarter::Infrastructure::DB::WebhookDeliveryRepository.new(TestDatabase.database)
      .list_for_endpoint("whk_legacy_egress")
    deliveries.first.status.should eq "failed"
  ensure
    receiver.try(&.stop)
  end

  it "rejects DNS answers containing any private address, including mixed A/AAAA records" do
    resolver = EgressTestResolver.new(["93.184.216.34", "fc00::1"])
    service = egress_test_service(KemalcrStarter::App.settings, "https://example.com/hooks", resolver)
    expect_raises(Exception, /webhook_delivery_failed/) do
      service.dispatch_event(KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_egress"))
    end
    deliveries = KemalcrStarter::Infrastructure::DB::WebhookDeliveryRepository.new(TestDatabase.database).list_for_endpoint("whk_egress_transport")
    deliveries.first.status.should eq "failed"
    deliveries.first.last_error.not_nil!.should contain "not permitted"
  end

  it "connects to the validated address and preserves the original Host and signature" do
    receiver = KemalcrStarter::WebhookReceiver.new("secret")
    port = receiver.start("127.0.0.2")
    service = egress_test_service(egress_test_settings, "http://localhost:#{port}/hooks", EgressTestResolver.new(["127.0.0.2"]))
    service.dispatch_event(KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_egress"))
    received = receiver.wait_for_request
    received.headers["Host"].should eq "localhost:#{port}"
    receiver.verify_signature(received.body, received.headers["X-Webhook-Signature"]).should be_true
  ensure
    receiver.try(&.stop)
  end

  it "does not follow redirects to another local receiver" do
    source = KemalcrStarter::WebhookReceiver.new("secret")
    target = KemalcrStarter::WebhookReceiver.new("secret")
    target_port = target.start
    source.response_status = 302
    source.response_headers["Location"] = "http://127.0.0.1:#{target_port}/private"
    port = source.start
    service = egress_test_service(egress_test_settings, "http://localhost:#{port}/hooks", EgressTestResolver.new(["127.0.0.1"]))
    expect_raises(Exception, /webhook_delivery_failed/) do
      service.dispatch_event(KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_egress"))
    end
    source.requests.size.should eq 1
    target.requests.should be_empty
  ensure
    source.try(&.stop)
    target.try(&.stop)
  end

  it "cannot enable loopback access in production by setting the test option" do
    policy = KemalcrStarter::Infrastructure::Http::WebhookDestination.new(egress_test_settings.copy_with(environment: "production"))
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { policy.validate!("http://127.0.0.1/hooks") }
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { policy.validate!("https://127.0.0.1/hooks") }
  end

  it "finishes on response headers without reading a gzip response body" do
    server = HTTP::Server.new do |context|
      context.request.body.try(&.gets_to_end)
      context.response.headers["Content-Encoding"] = "gzip"
      context.response.print "invalid gzip body"
    end
    port = server.bind_tcp("127.0.0.1", 0).port
    spawn { server.listen }
    service = egress_test_service(egress_test_settings, "http://localhost:#{port}/hooks", EgressTestResolver.new(["127.0.0.1"]))
    begin
      service.dispatch_event(KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_egress"))
    rescue ex
      ex.message.not_nil!.should contain "webhook_delivery_failed"
    end
    delivery = KemalcrStarter::Infrastructure::DB::WebhookDeliveryRepository.new(TestDatabase.database).list_for_endpoint("whk_egress_transport").first
    delivery.status.should eq "delivered"
  ensure
    server.try(&.close)
  end

  [{true, "localhost", true}, {false, "localhost", false}, {true, "127.0.0.1", false}].each do |trusted, hostname, allowed|
    it "#{allowed ? "accepts" : "rejects"} TLS trusted=#{trusted} hostname=#{hostname}" do
      previous_ca = ENV["SSL_CERT_FILE"]?
      ENV["SSL_CERT_FILE"] = File.expand_path("spec/fixtures/webhook_tls/localhost-cert.pem") if trusted
      server_context = OpenSSL::SSL::Context::Server.new
      server_context.certificate_chain = "spec/fixtures/webhook_tls/localhost-cert.pem"
      server_context.private_key = "spec/fixtures/webhook_tls/test-only-localhost-key.pem"
      received = [] of HTTP::Headers
      server = HTTP::Server.new do |context|
        context.request.body.try(&.gets_to_end)
        received << context.request.headers.dup
        context.response.print "ok"
      end
      port = server.bind_tls("127.0.0.2", 0, server_context).port
      spawn { server.listen }
      service = egress_test_service(egress_test_settings, "https://#{hostname}:#{port}/hooks", EgressTestResolver.new(["127.0.0.2"]))
      event = KemalcrStarter::Modules::Organizations::OrganizationUpdated.new("org_egress")
      if allowed
        service.dispatch_event(event)
        received.size.should eq 1
        received.first["Host"].should eq "localhost:#{port}"
      else
        expect_raises(Exception, /webhook_delivery_failed/) { service.dispatch_event(event) }
        received.should be_empty
      end
    ensure
      server.try(&.close)
      if previous_ca
        ENV["SSL_CERT_FILE"] = previous_ca
      else
        ENV.delete("SSL_CERT_FILE")
      end
    end
  end

  it "revalidates changed DNS answers on the next delivery resolution" do
    resolver = EgressTestResolver.new(["93.184.216.34", "2606:4700:4700::1111"])
    policy = KemalcrStarter::Infrastructure::Http::WebhookDestination.new(KemalcrStarter::App.settings, resolver)
    uri = policy.validate!("https://example.com/hooks")
    policy.resolve!(uri).address.should eq "93.184.216.34"
    resolver.addresses = ["169.254.169.254"]
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { policy.resolve!(uri) }
  end

  it "rejects an empty DNS result" do
    policy = KemalcrStarter::Infrastructure::Http::WebhookDestination.new(KemalcrStarter::App.settings, EgressTestResolver.new([] of String))
    uri = policy.validate!("https://example.com/hooks")
    expect_raises(KemalcrStarter::Core::Errors::ValidationError) { policy.resolve!(uri) }
  end

  it "does not reject 192.0.1.1 as part of the 192.0.0.0/24 special range" do
    policy = KemalcrStarter::Infrastructure::Http::WebhookDestination.new(KemalcrStarter::App.settings)
    hostname = begin
      policy.validate!("https://192.0.1.1/hooks").hostname
    rescue KemalcrStarter::Core::Errors::ValidationError
      nil
    end
    hostname.should eq "192.0.1.1"
  end
end
