require "uuid"

module KemalcrStarter
  module Modules
    module Identity
      class AuthService
        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database,
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil)
          @password_hasher = Infrastructure::Crypto::PasswordHasher.new(@settings.password_pepper, @settings.password_hash_cost)
          @token_fingerprint = Infrastructure::Crypto::TokenFingerprint.new(@settings.password_pepper)
          @token_provider = Infrastructure::Jwt::TokenProvider.new(
            @settings.jwt_secret,
            @settings.service_name,
            @settings.jwt_access_ttl_minutes,
            @settings.jwt_refresh_ttl_days
          )
          @user_repository = Infrastructure::DB::UserRepository.new(@database)
          @session_repository = Infrastructure::DB::UserSessionRepository.new(@database)
          @membership_repository = Infrastructure::DB::OrganizationMembershipRepository.new(@database)
        end

        def password_hasher : Infrastructure::Crypto::PasswordHasher
          @password_hasher
        end

        def login(email : String, password : String, user_agent : String?, ip_address : String?) : Infrastructure::Jwt::TokenPairResponse
          normalized_email = email.strip.downcase
          user = @user_repository.find_credentials_by_email(normalized_email)

          raise_invalid_credentials unless valid_login?(user, password)

          now = Time.utc
          session_id = generate_id("ses")
          session_family_id = generate_id("fam")
          active_organization_id = default_active_organization_id(user.not_nil!.id)
          issued_tokens = @token_provider.issue_token_pair(user.not_nil!.id, session_id, session_family_id, active_organization_id, now: now)
          refresh_token_hash = @token_fingerprint.digest(issued_tokens.refresh_token)

          @database.transaction do |txn|
            connection = txn.connection
            user_repository = Infrastructure::DB::UserRepository.new(connection)
            session_repository = Infrastructure::DB::UserSessionRepository.new(connection)

            session_repository.create(
              id: session_id,
              user_id: user.not_nil!.id,
              session_family_id: session_family_id,
              refresh_token_hash: refresh_token_hash,
              expires_at: issued_tokens.refresh_expires_at,
              user_agent: user_agent,
              ip_address: ip_address
            )
            user_repository.touch_last_login(user.not_nil!.id, now)
          end

          publish_event(UserLoggedIn.new(user.not_nil!.id))
          issued_tokens.to_response
        end

        def refresh(refresh_token : String, user_agent : String?, ip_address : String?) : Infrastructure::Jwt::TokenPairResponse
          claims = @token_provider.decode_refresh_token(refresh_token)
          session = @session_repository.find(claims.session_id)
          now = Time.utc

          raise_invalid_refresh unless session
          raise_invalid_refresh unless session.not_nil!.user_id == claims.user_id
          raise_invalid_refresh unless session.not_nil!.session_family_id == claims.session_family_id

          if session.not_nil!.revoked_at
            @session_repository.revoke_family(session.not_nil!.session_family_id, now)
            raise Core::Errors::ConflictError.new("Refresh token reuse detected.")
          end

          if session.not_nil!.expires_at <= now
            raise_invalid_refresh
          end

          if session.not_nil!.refresh_token_hash != @token_fingerprint.digest(refresh_token)
            @session_repository.revoke_family(session.not_nil!.session_family_id, now)
            raise Core::Errors::ConflictError.new("Refresh token reuse detected.")
          end

          user = @user_repository.find_credentials(session.not_nil!.user_id)
          raise_invalid_refresh unless user
          raise_invalid_refresh unless user.not_nil!.status == "active"

          new_session_id = generate_id("ses")
          active_organization_id = default_active_organization_id(user.not_nil!.id)
          issued_tokens = @token_provider.issue_token_pair(user.not_nil!.id, new_session_id, session.not_nil!.session_family_id, active_organization_id, now: now)
          refresh_token_hash = @token_fingerprint.digest(issued_tokens.refresh_token)

          @database.transaction do |txn|
            connection = txn.connection
            session_repository = Infrastructure::DB::UserSessionRepository.new(connection)

            session_repository.revoke(session.not_nil!.id, now)
            session_repository.create(
              id: new_session_id,
              user_id: user.not_nil!.id,
              session_family_id: session.not_nil!.session_family_id,
              refresh_token_hash: refresh_token_hash,
              expires_at: issued_tokens.refresh_expires_at,
              user_agent: user_agent,
              ip_address: ip_address,
              rotated_from_id: session.not_nil!.id
            )
          end

          issued_tokens.to_response
        end

        def decode_refresh_actor_id(refresh_token : String) : String
          @token_provider.decode_refresh_token(refresh_token).user_id
        end

        def logout(access_token : String) : Nil
          claims = authenticate_access_token(access_token)
          @session_repository.revoke(claims.session_id, Time.utc)
          publish_event(SessionRevoked.new(claims.user_id, claims.session_id))
        end

        def logout_all(access_token : String) : Nil
          claims = authenticate_access_token(access_token)
          @session_repository.revoke_all_for_user(claims.user_id, Time.utc)
          publish_event(UserLoggedOut.new(claims.user_id))
        end

        def switch_active_organization(access_token : String, organization_id : String, user_agent : String?, ip_address : String?) : Infrastructure::Jwt::TokenPairResponse
          claims = authenticate_access_token(access_token)
          membership = @membership_repository.find_active_for_user_and_organization(claims.user_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor is not a member of the requested organization.") unless membership

          session = @session_repository.find(claims.session_id)
          raise Core::Errors::UnauthorizedError.new unless session

          now = Time.utc
          new_session_id = generate_id("ses")
          issued_tokens = @token_provider.issue_token_pair(
            claims.user_id,
            new_session_id,
            session.not_nil!.session_family_id,
            organization_id,
            now: now
          )
          refresh_token_hash = @token_fingerprint.digest(issued_tokens.refresh_token)

          @database.transaction do |txn|
            connection = txn.connection
            session_repository = Infrastructure::DB::UserSessionRepository.new(connection)

            session_repository.revoke(session.not_nil!.id, now)
            session_repository.create(
              id: new_session_id,
              user_id: claims.user_id,
              session_family_id: session.not_nil!.session_family_id,
              refresh_token_hash: refresh_token_hash,
              expires_at: issued_tokens.refresh_expires_at,
              user_agent: user_agent,
              ip_address: ip_address,
              rotated_from_id: session.not_nil!.id
            )
          end

          issued_tokens.to_response
        end

        def authenticate_access_token(access_token : String) : Infrastructure::Jwt::AccessTokenClaims
          claims = @token_provider.decode_access_token(access_token)
          raise Core::Errors::UnauthorizedError.new unless @session_repository.active?(claims.session_id, claims.user_id)

          claims
        end

        private def valid_login?(user : Infrastructure::DB::UserCredentialsRecord?, password : String) : Bool
          return false unless user
          return false unless user.status == "active"

          @password_hasher.verify(password, user.password_digest)
        end

        private def generate_id(prefix : String) : String
          "#{prefix}_#{UUID.random}"
        end

        private def default_active_organization_id(user_id : String) : String?
          @membership_repository.find_primary_active_for_user(user_id).try(&.organization_id)
        end

        private def raise_invalid_credentials : NoReturn
          raise Core::Errors::UnauthorizedError.new("Invalid email or password.")
        end

        private def raise_invalid_refresh : NoReturn
          raise Core::Errors::UnauthorizedError.new("Refresh token is invalid or expired.")
        end

        private def publish_event(event : Core::Events::DomainEvent) : Nil
          repo = @event_repository
          repo.try(&.create(event))
        end
      end
    end
  end
end
