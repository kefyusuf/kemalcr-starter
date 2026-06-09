module KemalcrStarter
  module Modules
    module Identity
      class MeService
        def initialize(@database : ::DB::Database)
          @user_repository = Infrastructure::DB::UserRepository.new(@database)
          @organization_repository = Infrastructure::DB::OrganizationRepository.new(@database)
          @membership_repository = Infrastructure::DB::OrganizationMembershipRepository.new(@database)
        end

        def response_for(actor_id : String, active_organization_id : String?)
          user = @user_repository.find(actor_id)
          raise Core::Errors::UnauthorizedError.new unless user

          membership = resolve_membership(actor_id, active_organization_id)
          organization = membership ? @organization_repository.find_active(membership.not_nil!.organization_id) : nil

          if active_organization_id && membership.nil?
            raise Core::Errors::ForbiddenError.new("Active organization is not available for this actor.")
          end

          {
            user: {
              id:     user.not_nil!.id,
              email:  user.not_nil!.email,
              status: user.not_nil!.status,
            },
            active_organization: organization ? {
              id:   organization.not_nil!.id,
              slug: organization.not_nil!.slug,
              name: organization.not_nil!.name,
            } : nil,
            membership: membership ? {
              organization_id: membership.not_nil!.organization_id,
              role:            membership.not_nil!.role,
              status:          membership.not_nil!.status,
            } : nil,
          }
        end

        private def resolve_membership(actor_id : String, active_organization_id : String?)
          if active_organization_id
            @membership_repository.find_active_for_user_and_organization(actor_id, active_organization_id)
          else
            @membership_repository.find_primary_active_for_user(actor_id)
          end
        end
      end
    end
  end
end
