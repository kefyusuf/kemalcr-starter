module KemalcrStarter
  module Infrastructure
    module DB
      record ProductRecord,
        id : String,
        organization_id : String,
        sku : String,
        name : String,
        description : String?,
        price_cents : Int32,
        currency : String,
        status : String,
        created_by : String?,
        created_at : Time,
        updated_at : Time

      class ProductRepository < Repository
        def create(id : String, organization_id : String, sku : String, name : String,
                   description : String?, price_cents : Int32, currency : String,
                   created_by : String?) : ProductRecord
          now = Time.utc
          exec(
            <<-SQL,
              INSERT INTO products (
                id, organization_id, sku, name, description, price_cents, currency, created_by, created_at, updated_at
              )
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)
            SQL
            id, organization_id, sku, name, description, price_cents, currency, created_by, now
          )
          find(id).not_nil!
        end

        def find(id : String) : ProductRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, sku, name, description, price_cents, currency, status, created_by, created_at, updated_at
              FROM products
              WHERE id = $1
            SQL
            id
          ) do |rs|
            map_product(rs)
          end
        end

        def list_for_organization(organization_id : String, status : String? = nil, limit : Int32 = 50, offset : Int32 = 0) : Array(ProductRecord)
          if status
            many(
              <<-SQL,
                SELECT id, organization_id, sku, name, description, price_cents, currency, status, created_by, created_at, updated_at
                FROM products
                WHERE organization_id = $1 AND status = $2
                ORDER BY created_at DESC
                LIMIT $3 OFFSET $4
              SQL
              organization_id, status, limit, offset
            ) do |rs|
              map_product(rs)
            end
          else
            many(
              <<-SQL,
                SELECT id, organization_id, sku, name, description, price_cents, currency, status, created_by, created_at, updated_at
                FROM products
                WHERE organization_id = $1
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
              SQL
              organization_id, limit, offset
            ) do |rs|
              map_product(rs)
            end
          end
        end

        def update(id : String, name : String?, description : String?, price_cents : Int32?, status : String?) : ProductRecord?
          current = find(id)
          return nil unless current

          exec(
            <<-SQL,
              UPDATE products
              SET name = $2,
                  description = $3,
                  price_cents = $4,
                  status = $5,
                  updated_at = NOW()
              WHERE id = $1
            SQL
            id,
            name || current.name,
            description.nil? ? current.description : description,
            price_cents || current.price_cents,
            status || current.status
          )
          find(id)
        end

        def delete(id : String) : Bool
          result = exec("DELETE FROM products WHERE id = $1", id)
          result.rows_affected > 0
        end

        private def map_product(rs : ::DB::ResultSet) : ProductRecord
          ProductRecord.new(
            id: rs.read(String),
            organization_id: rs.read(String),
            sku: rs.read(String),
            name: rs.read(String),
            description: rs.read(String?),
            price_cents: rs.read(Int32),
            currency: rs.read(String),
            status: rs.read(String),
            created_by: rs.read(String?),
            created_at: rs.read(Time),
            updated_at: rs.read(Time)
          )
        end
      end
    end
  end
end
