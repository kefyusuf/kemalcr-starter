require "./permission"

module KemalcrStarter
  module Core
    module Rbac
      class AuthorizationService
        ALL_PERMISSIONS = Permission.values.to_set

        OWNER_PERMISSIONS = ALL_PERMISSIONS

        ADMIN_PERMISSIONS = ALL_PERMISSIONS - Set{
          Permission::OrganizationDelete,
        }

        MEMBER_PERMISSIONS = Set{
          Permission::OrganizationListMemberships,
          Permission::ProductList,
        }

        ROLE_PERMISSIONS = {
          "owner"  => OWNER_PERMISSIONS,
          "admin"  => ADMIN_PERMISSIONS,
          "member" => MEMBER_PERMISSIONS,
        }

        def initialize(@repository : Infrastructure::DB::RbacRepository)
        end

        def authorize!(actor_id : String, organization_id : String, permission : Permission,
                       role : String? = nil) : Nil
          raise Core::Errors::ForbiddenError.new("Access denied.") unless authorized?(
                                                                            actor_id, organization_id, permission, role
                                                                          )
        end

        def authorized?(actor_id : String, organization_id : String, permission : Permission,
                        role : String? = nil) : Bool
          resolved_role = role
          if resolved_role.nil?
            membership = find_membership(actor_id, organization_id)
            return false unless membership
            resolved_role = membership.role
          end

          has_permission?(resolved_role.not_nil!, permission)
        end

        def has_permission?(role_name : String, permission : Permission) : Bool
          ROLE_PERMISSIONS.fetch(role_name, Set(Permission).new).includes?(permission)
        end

        def roles_for_permission(permission : Permission) : Array(String)
          ROLE_PERMISSIONS.select { |_role, perms| perms.includes?(permission) }.keys
        end

        def seed_default_roles! : Nil
          ROLE_PERMISSIONS.each do |role_name, permissions|
            @repository.seed_role(role_name, permissions)
          end
        end

        private def find_membership(actor_id : String, organization_id : String) : Infrastructure::DB::OrganizationMembershipRecord?
          @repository.find_active_membership(actor_id, organization_id)
        end
      end
    end
  end
end
