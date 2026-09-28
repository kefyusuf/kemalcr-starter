require "./spec_helper"
require "openssl/hmac"

module KemalcrStarter
  describe Infrastructure::Billing::StripeWebhookVerifier do
    it "accepts a valid Stripe signature" do
      secret = "whsec_test"
      payload = %({"id":"evt_1","type":"checkout.session.completed"})
      timestamp = Time.utc.to_unix
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, "#{timestamp}.#{payload}")
      header = "t=#{timestamp},v1=#{signature}"

      verifier = Infrastructure::Billing::StripeWebhookVerifier.new(secret, 300)
      verifier.verify(payload, header).should be_true
    end

    it "rejects tampered payloads and stale timestamps" do
      secret = "whsec_test"
      payload = %({"id":"evt_1"})
      timestamp = Time.utc.to_unix
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, "#{timestamp}.#{payload}")

      verifier = Infrastructure::Billing::StripeWebhookVerifier.new(secret, 300)
      verifier.verify(payload + "x", "t=#{timestamp},v1=#{signature}").should be_false
      verifier.verify(payload, "t=#{timestamp - 3600},v1=#{signature}").should be_false
      verifier.verify(payload, nil).should be_false
      verifier.verify(payload, "t=#{timestamp},v1=deadbeef").should be_false
    end
  end

  describe Modules::Billing::BillingService do
    it "handles signed stripe webhooks and publishes billing events" do
      TestDatabase.truncate_all!

      settings = App.settings
      # Build a settings-like service with webhook secret via env override in verifier path
      ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_e2e"
      ENV["BILLING_ADAPTER"] = "null"
      App.reset_services

      service = Modules::Billing::BillingService.new(
        App.settings,
        TestDatabase.database,
        Infrastructure::Billing::NullBillingAdapter.new,
        Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database)
      )

      payload = %({"id":"evt_abc","type":"checkout.session.completed","data":{"object":{"id":"cs_1","metadata":{"organization_id":"org_1"}}}})
      timestamp = Time.utc.to_unix
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, "whsec_e2e", "#{timestamp}.#{payload}")
      header = "t=#{timestamp},v1=#{signature}"

      service.handle_stripe_webhook(payload, header).should eq("ok")

      events = Infrastructure::DB::OutboxEventRepository.new(TestDatabase.database).next_batch(10)
      events.size.should eq(1)
      events.first.event_type.should eq("billing.checkout.completed")
      events.first.event_data.should contain("cs_1")

      expect_raises(Core::Errors::UnauthorizedError) do
        service.handle_stripe_webhook(payload, "t=#{timestamp},v1=bogus")
      end
    end
  end
end
