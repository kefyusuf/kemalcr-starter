module KemalcrStarter
  module Infrastructure
    module DB
      record RbacRolePermissionRecord,
        id : String,
        role_name : String,
        permission_name : String,
        created_at : Time

      class RbacRepository < Repository
        def role_has_permission?(role_name : String, permission : Core::Rbac::Permission) : Bool
          existing = one? "SELECT 1 FROM rbac_role_permissions WHERE role_name = $1 AND permission_name = $2",
            role_name, permission.to_s do |rs|
            rs.read(Int32)
          end
          !existing.nil?
        end

        def list_permissions_for_role(role_name : String) : Array(String)
          many(
            <<-SQL,
              SELECT permission_name FROM rbac_role_permissions
              WHERE role_name = $1
              ORDER BY permission_name ASC
            SQL
            role_name
          ) do |rs|
            rs.read(String)
          end
        end

        def assign_permission(role_name : String, permission : Core::Rbac::Permission) : Nil
          exec "INSERT INTO rbac_role_permissions (role_name, permission_name) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            role_name, permission.to_s
        end

        def remove_permission(role_name : String, permission : Core::Rbac::Permission) : Nil
          exec "DELETE FROM rbac_role_permissions WHERE role_name = $1 AND permission_name = $2",
            role_name, permission.to_s
        end

        def seed_role(role_name : String, permissions : Enumerable(Core::Rbac::Permission)) : Nil
          permissions.each do |perm|
            exec "INSERT INTO rbac_role_permissions (role_name, permission_name) VALUES ($1, $2) ON CONFLICT DO NOTHING",
              role_name, perm.to_s
          end
        end

        def clear_role(role_name : String) : Nil
          exec "DELETE FROM rbac_role_permissions WHERE role_name = $1", role_name
        end

        def find_active_membership(actor_id : String, organization_id : String) : OrganizationMembershipRecord?
          one? "SELECT id, organization_id, user_id, role, status FROM organization_memberships WHERE organization_id = $1 AND user_id = $2 AND status = 'active'",
            organization_id, actor_id do |rs|
            OrganizationMembershipRecord.new(
              id: rs.read(String),
              organization_id: rs.read(String),
              user_id: rs.read(String),
              role: rs.read(String),
              status: rs.read(String)
            )
          end
        end
      end
    end
  end
end
