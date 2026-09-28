require "./spec_helper"
require "./support/db/test_database"

module KemalcrStarter
  class RecordingEmailAdapter < Infrastructure::Email::EmailAdapter
    getter messages : Array(Infrastructure::Email::EmailMessage)

    def initialize
      @messages = [] of Infrastructure::Email::EmailMessage
    end

    def deliver(message : Infrastructure::Email::EmailMessage) : Nil
      @messages << message
    end
  end

  describe Modules::Identity::PasswordResetService do
    it "requests a reset and delivers email via adapter without leaking user existence" do
      TestDatabase.truncate_all!
      settings = App.settings
      email_adapter = RecordingEmailAdapter.new
      App.install_email_adapter(email_adapter)

      service = Modules::Identity::PasswordResetService.new(
        settings,
        TestDatabase.database,
        email_adapter
      )

      service.request_reset("missing@example.com")
      email_adapter.messages.size.should eq(0)

      user_id = "usr_test"
      hasher = Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)
      Infrastructure::DB::UserRepository.new(TestDatabase.database).create(
        id: user_id,
        email: "reset@example.com",
        name: "Reset User",
        password_digest: hasher.hash("OldPass1!")
      )

      service.request_reset("reset@example.com")
      email_adapter.messages.size.should eq(1)
      email_adapter.messages.first.to.should eq("reset@example.com")
      email_adapter.messages.first.body.should contain("token=")
    end

    it "confirms reset, updates password, and revokes sessions" do
      TestDatabase.truncate_all!
      settings = App.settings
      email_adapter = RecordingEmailAdapter.new
      service = Modules::Identity::PasswordResetService.new(settings, TestDatabase.database, email_adapter)

      user_id = "usr_reset"
      hasher = Infrastructure::Crypto::PasswordHasher.new(settings.password_pepper, settings.password_hash_cost)
      users = Infrastructure::DB::UserRepository.new(TestDatabase.database)
      sessions = Infrastructure::DB::UserSessionRepository.new(TestDatabase.database)

      users.create(id: user_id, email: "confirm@example.com", name: "Confirm", password_digest: hasher.hash("OldPass1!"))
      sessions.create(
        id: "ses_1",
        user_id: user_id,
        session_family_id: "fam_1",
        refresh_token_hash: "hash",
        expires_at: Time.utc + 1.day
      )

      service.request_reset("confirm@example.com")
      raw_token = email_adapter.messages.first.body.split("token=").last.split("\n").first
      service.confirm_reset(raw_token, "NewPass1!")

      credentials = users.find_credentials(user_id).not_nil!
      hasher.verify("NewPass1!", credentials.password_digest).should be_true
      hasher.verify("OldPass1!", credentials.password_digest).should be_false
      sessions.active?("ses_1", user_id).should be_false
    end

    it "rejects invalid tokens" do
      TestDatabase.truncate_all!
      settings = App.settings
      service = Modules::Identity::PasswordResetService.new(settings, TestDatabase.database, RecordingEmailAdapter.new)

      expect_raises(Core::Errors::UnauthorizedError) do
        service.confirm_reset("not-a-real-token", "NewPass1!")
      end
    end
  end
end
