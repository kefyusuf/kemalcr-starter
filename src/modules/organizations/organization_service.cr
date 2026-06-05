require "uuid"

module KemalcrStarter
  module Modules
    module Organizations
      class OrganizationService
        def initialize(@database : ::DB::Database,
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil,
                       @rbac_service : Core::Rbac::AuthorizationService? = nil)
          @organization_repository = Infrastructure::DB::OrganizationRepository.new(@database)
          @membership_repository = Infrastructure::DB::OrganizationMembershipRepository.new(@database)
          @user_repository = Infrastructure::DB::UserRepository.new(@database)
        end

        def list_for_actor(actor_id : String)
          @organization_repository.list_active_for_user(actor_id).map do |organization|
            serialize_organization(organization)
          end
        end

        def get_for_actor(actor_id : String, organization_id : String)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.") unless membership

          organization = @organization_repository.find_active(organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.") unless organization

          serialize_organization(organization.not_nil!)
        end

        def get_for_request(actor_id : String?, authenticated_organization_id : String?, organization_id : String)
          return get_for_actor(actor_id.not_nil!, organization_id) if actor_id

          if authenticated_organization_id == organization_id
            organization = @organization_repository.find_active(organization_id)
            raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.") unless organization

            return serialize_organization(organization.not_nil!)
          end

          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.")
        end

        def create_for_actor(actor_id : String, slug : String, name : String)
          normalized_slug = normalize_slug(slug)
          normalized_name = name.strip
          raise Core::Errors::ValidationError.new if normalized_slug.empty? || normalized_name.empty?

          organization_id = generate_id("org")
          membership_id = generate_id("mem")

          organization = @database.transaction do |txn|
            connection = txn.connection
            organization_repository = Infrastructure::DB::OrganizationRepository.new(connection)
            membership_repository = Infrastructure::DB::OrganizationMembershipRepository.new(connection)

            created = organization_repository.create(organization_id, normalized_slug, normalized_name, actor_id)
            membership_repository.create(membership_id, organization_id, actor_id, "owner", joined_at: Time.utc)
            created
          end.not_nil!

          publish_event(OrganizationCreated.new(organization_id, normalized_name, actor_id))
          serialize_organization(organization)
        rescue ::DB::Error
          raise Core::Errors::ConflictError.new("Organization slug already exists.")
        end

        def update_for_actor(actor_id : String, organization_id : String, slug : String?, name : String?)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot update this organization.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::OrganizationUpdate, role: membership.not_nil!.role)

          normalized_slug = slug.nil? ? nil : normalize_slug(slug)
          normalized_name = name.nil? ? nil : name.strip
          raise Core::Errors::ValidationError.new if normalized_slug == "" || normalized_name == ""
          raise Core::Errors::ValidationError.new if normalized_slug.nil? && normalized_name.nil?

          organization = @organization_repository.update(organization_id, normalized_slug, normalized_name)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot update this organization.") unless organization

          publish_event(OrganizationUpdated.new(organization_id))
          serialize_organization(organization.not_nil!)
        rescue ::DB::Error
          raise Core::Errors::ConflictError.new("Organization slug already exists.")
        end

        def list_memberships_for_actor(actor_id : String, organization_id : String)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::OrganizationListMemberships, role: membership.not_nil!.role)

          organization = @organization_repository.find_active(organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.") unless organization

          @membership_repository.list_active_for_organization(organization_id).map do |member|
            serialize_membership(member)
          end
        end

        def list_memberships_for_request(actor_id : String?, authenticated_organization_id : String?, organization_id : String)
          return list_memberships_for_actor(actor_id.not_nil!, organization_id) if actor_id

          if authenticated_organization_id == organization_id
            organization = @organization_repository.find_active(organization_id)
            raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.") unless organization

            return @membership_repository.list_active_for_organization(organization_id).map do |member|
              serialize_membership(member)
            end
          end

          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization.")
        end

        def list_invitations_for_actor(actor_id : String, organization_id : String)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization's invitations.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::OrganizationListInvitations, role: membership.not_nil!.role)

          organization = @organization_repository.find_active(organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot access this organization's invitations.") unless organization

          @membership_repository.list_pending_for_organization(organization_id).map do |invitation|
            serialize_invitation(invitation)
          end
        end

        def invite_user_for_actor(actor_id : String, organization_id : String, email : String, role : String)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot invite users to this organization.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::OrganizationInvite, role: membership.not_nil!.role)

          organization = @organization_repository.find_active(organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot invite users to this organization.") unless organization

          normalized_email = email.strip.downcase
          normalized_role = role.strip.downcase
          raise Core::Errors::ValidationError.new if normalized_email.empty?
          raise Core::Errors::ValidationError.new unless invite_role?(normalized_role)

          invitee = @user_repository.find_credentials_by_email(normalized_email)
          raise Core::Errors::ValidationError.new("Invitee must exist and be active.") unless invitee && invitee.not_nil!.status == "active"

          created = @membership_repository.create(
            generate_id("mem"),
            organization_id,
            invitee.not_nil!.id,
            normalized_role,
            status: "pending",
            invited_by_user_id: actor_id
          )

          publish_event(MembershipInvited.new(created.id, organization_id, normalized_email, normalized_role))
          serialize_invitation(created)
        rescue ::DB::Error
          raise Core::Errors::ConflictError.new("An invitation or membership already exists for this user.")
        end

        def accept_invitation_for_actor(actor_id : String, organization_id : String, invitation_id : String)
          invitation = @membership_repository.find_pending(invitation_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot accept this invitation.") unless invitation
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot accept this invitation.") unless invitation.not_nil!.organization_id == organization_id
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot accept this invitation.") unless invitation.not_nil!.user_id == actor_id

          organization = @organization_repository.find_active(organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot accept this invitation.") unless organization

          activated = @membership_repository.update_status(invitation_id, "active", Time.utc)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot accept this invitation.") unless activated

          publish_event(MembershipAccepted.new(invitation_id, organization_id))
          serialize_membership(activated.not_nil!)
        end

        def revoke_invitation_for_actor(actor_id : String, organization_id : String, invitation_id : String)
          membership = @membership_repository.find_active_for_user_and_organization(actor_id, organization_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot revoke this invitation.") unless membership
          @rbac_service.not_nil!.authorize!(actor_id, organization_id, Core::Rbac::Permission::OrganizationRevoke, role: membership.not_nil!.role)

          invitation = @membership_repository.find_pending(invitation_id)
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot revoke this invitation.") unless invitation
          raise Core::Errors::ForbiddenError.new("The authenticated actor cannot revoke this invitation.") unless invitation.not_nil!.organization_id == organization_id

          @membership_repository.update_status(invitation_id, "revoked")
          publish_event(MembershipRevoked.new(invitation_id, organization_id))
          nil
        end

        private def normalize_slug(slug : String) : String
          slug.strip.downcase.gsub(/[^a-z0-9\-]/, "-").gsub(/-+/, "-").gsub(/^-|-$/, "")
        end

        private def serialize_organization(organization : Infrastructure::DB::OrganizationRecord)
          {
            id:   organization.id,
            slug: organization.slug,
            name: organization.name,
          }
        end

        private def serialize_membership(membership : Infrastructure::DB::OrganizationMembershipRecord)
          {
            id:              membership.id,
            organization_id: membership.organization_id,
            user_id:         membership.user_id,
            role:            membership.role,
            status:          membership.status,
          }
        end

        private def serialize_invitation(membership : Infrastructure::DB::OrganizationMembershipRecord)
          invitee = @user_repository.find(membership.user_id)

          {
            id:              membership.id,
            organization_id: membership.organization_id,
            user_id:         membership.user_id,
            email:           invitee.try(&.email) || "",
            role:            membership.role,
            status:          membership.status,
          }
        end

        private def generate_id(prefix : String) : String
          "#{prefix}_#{UUID.random}"
        end

        private def invite_role?(role : String) : Bool
          role == "admin" || role == "member"
        end

        private def publish_event(event : Core::Events::DomainEvent) : Nil
          repo = @event_repository
          repo.try(&.create(event))
        end
      end
    end
  end
end
