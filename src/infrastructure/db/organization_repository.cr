module KemalcrStarter
  module Infrastructure
    module DB
      record OrganizationRecord,
        id : String,
        slug : String,
        name : String,
        status : String,
        owner_user_id : String

      class OrganizationRepository < Repository
        def create(id : String, slug : String, name : String, owner_user_id : String, status : String = "active") : OrganizationRecord
          exec(
            <<-SQL,
              INSERT INTO organizations (id, slug, name, status, owner_user_id)
              VALUES ($1, $2, $3, $4, $5)
            SQL
            id,
            slug,
            name,
            status,
            owner_user_id
          )

          find(id).not_nil!
        end

        def count_active_for_user(user_id : String) : Int64
          one?(
            <<-SQL,
              SELECT COUNT(*)::bigint
              FROM organizations o
              INNER JOIN organization_memberships om
                ON om.organization_id = o.id
              WHERE om.user_id = $1
                AND om.status = 'active'
                AND o.status = 'active'
            SQL
            user_id
          ) do |rs|
            rs.read(Int64)
          end || 0_i64
        end

        def list_active_for_user(user_id : String, limit : Int32 = 1000, offset : Int32 = 0) : Array(OrganizationRecord)
          many(
            <<-SQL,
              SELECT o.id, o.slug, o.name, o.status, o.owner_user_id
              FROM organizations o
              INNER JOIN organization_memberships om
                ON om.organization_id = o.id
              WHERE om.user_id = $1
                AND om.status = 'active'
                AND o.status = 'active'
              ORDER BY o.created_at ASC
              LIMIT $2 OFFSET $3
            SQL
            user_id,
            limit,
            offset
          ) do |rs|
            OrganizationRecord.new(
              id: rs.read(String),
              slug: rs.read(String),
              name: rs.read(String),
              status: rs.read(String),
              owner_user_id: rs.read(String)
            )
          end
        end

        def find(id : String) : OrganizationRecord?
          one?(
            <<-SQL,
              SELECT id, slug, name, status, owner_user_id
              FROM organizations
              WHERE id = $1
            SQL
            id
          ) do |rs|
            OrganizationRecord.new(
              id: rs.read(String),
              slug: rs.read(String),
              name: rs.read(String),
              status: rs.read(String),
              owner_user_id: rs.read(String)
            )
          end
        end

        def find_active(id : String) : OrganizationRecord?
          one?(
            <<-SQL,
              SELECT id, slug, name, status, owner_user_id
              FROM organizations
              WHERE id = $1
                AND status = 'active'
            SQL
            id
          ) do |rs|
            OrganizationRecord.new(
              id: rs.read(String),
              slug: rs.read(String),
              name: rs.read(String),
              status: rs.read(String),
              owner_user_id: rs.read(String)
            )
          end
        end

        def update(id : String, slug : String?, name : String?) : OrganizationRecord?
          one?(
            <<-SQL,
              UPDATE organizations
              SET slug = COALESCE($2, slug),
                  name = COALESCE($3, name),
                  updated_at = NOW()
              WHERE id = $1
              RETURNING id, slug, name, status, owner_user_id
            SQL
            id,
            slug,
            name
          ) do |rs|
            OrganizationRecord.new(
              id: rs.read(String),
              slug: rs.read(String),
              name: rs.read(String),
              status: rs.read(String),
              owner_user_id: rs.read(String)
            )
          end
        end

        def delete_all : Nil
          exec "DELETE FROM organizations"
        end
      end
    end
  end
end
