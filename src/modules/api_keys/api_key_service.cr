require "uuid"

module KemalcrStarter
  module Modules
    module ApiKeys
      record AuthenticatedApiKey,
        api_key_id : String,
        organization_id : String

      class ApiKeyService
        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database,
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil,
                       @rbac_service : Core::Rbac::AuthorizationService? = nil)
          @api_key_repository = Infrastructure::DB::ApiKeyRepository.new(@database)
          @membership_repository = Infrastructure::DB::OrganizationMembershipRepository.new(@database)
          @organization_repository = Infrastructure::DB::OrganizationRepository.new(@database)
          @secret_hasher = Infrastructure::Crypto::ApiKeySecretHasher.new(@settings.password_pepper)
          @event_repository ||= Infrastructure::DB::OutboxEventRepository.new(@database)
        end

        def list_for_actor(actor_id : String, organization_id : String, limit : Int32 = 1000, offset : Int32 = 0)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization's API keys.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::ApiKeyCreate, role: membership.not_nil!.role)

          @api_key_repository.list_active_for_organization(organization_id, limit: limit, offset: offset).map do |api_key|
            serialize_api_key(api_key)
          end
        end

        def count_for_organization(organization_id : String) : Int64
          @api_key_repository.count_active_for_organization(organization_id)
        end

        def create_for_actor(actor_id : String, organization_id : String, name : String)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot create API keys for this organization.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::ApiKeyCreate, role: membership.not_nil!.role)

          normalized_name = name.strip
          raise Core::Errors::ValidationError.new if normalized_name.empty?

          secret = @secret_hasher.generate_secret
          created = @database.transaction do |txn|
            repository = Infrastructure::DB::ApiKeyRepository.new(txn.connection)
            key = repository.create(
              generate_id("key"),
              organization_id,
              normalized_name,
              @secret_hasher.prefix(secret),
              @secret_hasher.hash(secret)
            )
            publish_event(ApiKeyCreated.new(key.id, organization_id, normalized_name), txn.connection)
            key
          end.not_nil!
          serialize_created_api_key(created, secret)
        end

        def revoke_for_actor(actor_id : String, organization_id : String, api_key_id : String) : Nil
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot revoke API keys for this organization.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::ApiKeyRevoke, role: membership.not_nil!.role)

          api_key = @api_key_repository.find_active_for_organization(api_key_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot revoke API keys for this organization.") unless api_key

          @database.transaction do |txn|
            revoked = Infrastructure::DB::ApiKeyRepository.new(txn.connection).revoke(api_key_id, Time.utc)
            raise Core::Errors::ForbiddenError.new("The authenticated actor cannot revoke API keys for this organization.") unless revoked
            publish_event(ApiKeyRevoked.new(api_key_id, organization_id), txn.connection)
          end
        end

        def authenticate(secret : String) : AuthenticatedApiKey
          normalized_secret = secret.strip
          raise Core::Errors::UnauthorizedError.new if normalized_secret.empty?

          api_key = @api_key_repository.find_active_by_prefix(@secret_hasher.prefix(normalized_secret))
          raise Core::Errors::UnauthorizedError.new unless api_key
          raise Core::Errors::UnauthorizedError.new unless @secret_hasher.verify(normalized_secret, api_key.not_nil!.secret_hash)

          @api_key_repository.touch_last_used(api_key.not_nil!.id, Time.utc)
          AuthenticatedApiKey.new(api_key_id: api_key.not_nil!.id, organization_id: api_key.not_nil!.organization_id)
        end

        private def generate_id(prefix : String) : String
          "#{prefix}_#{UUID.random}"
        end

        private def serialize_api_key(api_key : Infrastructure::DB::ApiKeyRecord)
          {
            id:           api_key.id,
            name:         api_key.name,
            key_prefix:   api_key.key_prefix,
            last_used_at: api_key.last_used_at.try(&.to_rfc3339),
            expires_at:   api_key.expires_at.try(&.to_rfc3339),
            revoked_at:   api_key.revoked_at.try(&.to_rfc3339),
            created_at:   api_key.created_at.to_rfc3339,
          }
        end

        private def serialize_created_api_key(api_key : Infrastructure::DB::ApiKeyRecord, secret : String)
          {
            id:           api_key.id,
            name:         api_key.name,
            key_prefix:   api_key.key_prefix,
            last_used_at: api_key.last_used_at.try(&.to_rfc3339),
            expires_at:   api_key.expires_at.try(&.to_rfc3339),
            revoked_at:   api_key.revoked_at.try(&.to_rfc3339),
            created_at:   api_key.created_at.to_rfc3339,
            secret:       secret,
          }
        end

        private def publish_event(event : Core::Events::DomainEvent, connection : ::DB::Connection) : Nil
          @event_repository.not_nil!.create(event, connection: connection)
        end
      end
    end
  end
end
