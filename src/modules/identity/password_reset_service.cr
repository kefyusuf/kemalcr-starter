require "uuid"
require "digest/sha256"
require "random/secure"

module KemalcrStarter
  module Modules
    module Identity
      class PasswordResetService
        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database,
                       @email_adapter : Infrastructure::Email::EmailAdapter,
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil)
          @password_hasher = Infrastructure::Crypto::PasswordHasher.new(@settings.password_pepper, @settings.password_hash_cost)
          @token_fingerprint = Infrastructure::Crypto::TokenFingerprint.new(@settings.password_pepper)
          @user_repository = Infrastructure::DB::UserRepository.new(@database)
          @token_repository = Infrastructure::DB::PasswordResetTokenRepository.new(@database)
          @session_repository = Infrastructure::DB::UserSessionRepository.new(@database)
          @event_repository ||= Infrastructure::DB::OutboxEventRepository.new(@database)
        end

        # Always succeeds from the caller's perspective to avoid user enumeration.
        def request_reset(email : String) : Nil
          normalized = email.strip.downcase
          user = @user_repository.find_credentials_by_email(normalized)
          return unless user
          return unless user.status == "active"

          raw_token = Random::Secure.urlsafe_base64(32)
          token_hash = @token_fingerprint.digest(raw_token)
          expires_at = Time.utc + Time::Span.new(minutes: @settings.password_reset_ttl_minutes)

          @token_repository.invalidate_active_for_user(user.id)
          @token_repository.create(id: generate_id("prt"), user_id: user.id, token_hash: token_hash, expires_at: expires_at)

          reset_url = "#{@settings.password_reset_base_url}?token=#{raw_token}"
          @email_adapter.deliver(
            to: normalized,
            subject: "Reset your password",
            body: "Use this link to reset your password (valid for #{@settings.password_reset_ttl_minutes} minutes):\n#{reset_url}\n\nIf you did not request this, ignore this email."
          )
        end

        def confirm_reset(token : String, password : String) : Nil
          validate_password!(password)

          token_hash = @token_fingerprint.digest(token.strip)
          record = @token_repository.find_active_by_hash(token_hash)
          raise Core::Errors::UnauthorizedError.new("Reset token is invalid or expired.") unless record

          user = @user_repository.find_credentials(record.user_id)
          raise Core::Errors::UnauthorizedError.new("Reset token is invalid or expired.") unless user

          digest = @password_hasher.hash(password)
          @database.transaction do |txn|
            connection = txn.connection
            user_repository = Infrastructure::DB::UserRepository.new(connection)
            token_repository = Infrastructure::DB::PasswordResetTokenRepository.new(connection)
            session_repository = Infrastructure::DB::UserSessionRepository.new(connection)

            user_repository.update_password_digest(user.id, digest)
            token_repository.mark_used!(record.id)
            token_repository.invalidate_active_for_user(user.id)
            session_repository.revoke_all_for_user(user.id, Time.utc)
            publish_event(UserPasswordReset.new(user.id, user.email), connection)
          end
        end

        private def generate_id(prefix : String) : String
          "#{prefix}_#{UUID.random}"
        end

        private def validate_password!(password : String) : Nil
          raise Core::Errors::ValidationError.new("Password must be at least 8 characters.") if password.size < 8
          raise Core::Errors::ValidationError.new("Password must include at least one uppercase letter.") unless password =~ /[A-Z]/
          raise Core::Errors::ValidationError.new("Password must include at least one lowercase letter.") unless password =~ /[a-z]/
          raise Core::Errors::ValidationError.new("Password must include at least one digit.") unless password =~ /\d/
        end

        private def publish_event(event : Core::Events::DomainEvent, connection : ::DB::Connection) : Nil
          @event_repository.not_nil!.create(event, connection: connection)
        end
      end
    end
  end
end
