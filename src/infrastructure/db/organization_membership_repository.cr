module KemalcrStarter
  module Infrastructure
    module DB
      record OrganizationMembershipRecord,
        id : String,
        organization_id : String,
        user_id : String,
        role : String,
        status : String

      class OrganizationMembershipRepository < Repository
        def create(
          id : String,
          organization_id : String,
          user_id : String,
          role : String,
          status : String = "active",
          joined_at : Time? = nil,
          invited_by_user_id : String? = nil,
        ) : OrganizationMembershipRecord
          exec(
            <<-SQL,
              INSERT INTO organization_memberships (
                id,
                organization_id,
                user_id,
                role,
                status,
                joined_at,
                invited_by_user_id
              )
              VALUES ($1, $2, $3, $4, $5, $6, $7)
            SQL
            id,
            organization_id,
            user_id,
            role,
            status,
            joined_at,
            invited_by_user_id
          )

          find(id).not_nil!
        end

        def find(id : String) : OrganizationMembershipRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, user_id, role, status
              FROM organization_memberships
              WHERE id = $1
            SQL
            id
          ) do |rs|
            map_membership(rs)
          end
        end

        def find_pending(id : String) : OrganizationMembershipRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, user_id, role, status
              FROM organization_memberships
              WHERE id = $1
                AND status = 'pending'
            SQL
            id
          ) do |rs|
            map_membership(rs)
          end
        end

        def find_active_for_user_and_organization(user_id : String, organization_id : String) : OrganizationMembershipRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, user_id, role, status
              FROM organization_memberships
              WHERE user_id = $1
                AND organization_id = $2
                AND status = 'active'
            SQL
            user_id,
            organization_id
          ) do |rs|
            map_membership(rs)
          end
        end

        def find_primary_active_for_user(user_id : String) : OrganizationMembershipRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, user_id, role, status
              FROM organization_memberships
              WHERE user_id = $1
                AND status = 'active'
              ORDER BY created_at ASC
              LIMIT 1
            SQL
            user_id
          ) do |rs|
            map_membership(rs)
          end
        end

        def count_active_for_organization(organization_id : String) : Int64
          one?(
            <<-SQL,
              SELECT COUNT(*)::bigint
              FROM organization_memberships
              WHERE organization_id = $1
                AND status = 'active'
            SQL
            organization_id
          ) do |rs|
            rs.read(Int64)
          end || 0_i64
        end

        def count_pending_for_organization(organization_id : String) : Int64
          one?(
            <<-SQL,
              SELECT COUNT(*)::bigint
              FROM organization_memberships
              WHERE organization_id = $1
                AND status = 'pending'
            SQL
            organization_id
          ) do |rs|
            rs.read(Int64)
          end || 0_i64
        end

        def list_active_for_organization(organization_id : String, limit : Int32 = 1000, offset : Int32 = 0) : Array(OrganizationMembershipRecord)
          many(
            <<-SQL,
              SELECT id, organization_id, user_id, role, status
              FROM organization_memberships
              WHERE organization_id = $1
                AND status = 'active'
              ORDER BY created_at ASC
              LIMIT $2 OFFSET $3
            SQL
            organization_id,
            limit,
            offset
          ) do |rs|
            map_membership(rs)
          end
        end

        def list_pending_for_organization(organization_id : String, limit : Int32 = 1000, offset : Int32 = 0) : Array(OrganizationMembershipRecord)
          many(
            <<-SQL,
              SELECT id, organization_id, user_id, role, status
              FROM organization_memberships
              WHERE organization_id = $1
                AND status = 'pending'
              ORDER BY created_at ASC
              LIMIT $2 OFFSET $3
            SQL
            organization_id,
            limit,
            offset
          ) do |rs|
            map_membership(rs)
          end
        end

        def update_status(id : String, status : String, joined_at : Time? = nil) : OrganizationMembershipRecord?
          exec(
            <<-SQL,
              UPDATE organization_memberships
              SET status = $2,
                  joined_at = COALESCE($3, joined_at),
                  updated_at = NOW()
              WHERE id = $1
            SQL
            id,
            status,
            joined_at
          )

          find(id)
        end

        def delete_all : Nil
          exec "DELETE FROM organization_memberships"
        end

        private def map_membership(rs : ::DB::ResultSet) : OrganizationMembershipRecord
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
