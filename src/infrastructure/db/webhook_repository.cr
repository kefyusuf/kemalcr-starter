require "json"

module KemalcrStarter
  module Infrastructure
    module DB
      record WebhookEndpointRecord,
        id : String,
        organization_id : String,
        url : String,
        secret : String,
        description : String?,
        event_types : Array(String),
        active : Bool,
        created_by : String?,
        created_at : Time

      record WebhookDeliveryRecord,
        id : String,
        endpoint_id : String,
        event_id : String,
        event_type : String,
        status : String,
        attempt_count : Int32,
        response_status : Int32?,
        last_error : String?,
        delivered_at : Time?,
        created_at : Time

      class WebhookEndpointRepository < Repository
        def create(id : String, organization_id : String, url : String, secret : String,
                   description : String?, event_types : Array(String), created_by : String?) : WebhookEndpointRecord
          now = Time.utc
          exec(
            <<-SQL,
              INSERT INTO webhook_endpoints (id, organization_id, url, secret, description, event_types, created_by, created_at, updated_at)
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
            SQL
            id, organization_id, url, secret, description, event_types, created_by, now
          )
          find(id).not_nil!
        end

        def find(id : String) : WebhookEndpointRecord?
          one?(
            <<-SQL,
              SELECT id, organization_id, url, secret, description, event_types, active, created_by, created_at
              FROM webhook_endpoints
              WHERE id = $1
            SQL
            id
          ) do |rs|
            map_endpoint(rs)
          end
        end

        def list_for_organization(organization_id : String) : Array(WebhookEndpointRecord)
          many(
            <<-SQL,
              SELECT id, organization_id, url, secret, description, event_types, active, created_by, created_at
              FROM webhook_endpoints
              WHERE organization_id = $1
              ORDER BY created_at DESC
            SQL
            organization_id
          ) do |rs|
            map_endpoint(rs)
          end
        end

        def list_active_for_event_type(organization_id : String, event_type : String) : Array(WebhookEndpointRecord)
          many(
            <<-SQL,
              SELECT id, organization_id, url, secret, description, event_types, active, created_by, created_at
              FROM webhook_endpoints
              WHERE active = TRUE
                AND organization_id = $1
                AND (cardinality(event_types) = 0 OR $2 = ANY(event_types))
            SQL
            organization_id, event_type
          ) do |rs|
            map_endpoint(rs)
          end
        end

        def revoke(id : String) : Bool
          result = exec("UPDATE webhook_endpoints SET active = FALSE, updated_at = NOW() WHERE id = $1", id)
          result.rows_affected > 0
        end

        private def map_endpoint(rs : ::DB::ResultSet) : WebhookEndpointRecord
          WebhookEndpointRecord.new(
            id: rs.read(String),
            organization_id: rs.read(String),
            url: rs.read(String),
            secret: rs.read(String),
            description: rs.read(String?),
            event_types: rs.read(Array(String)),
            active: rs.read(Bool),
            created_by: rs.read(String?),
            created_at: rs.read(Time)
          )
        end
      end

      class WebhookDeliveryRepository < Repository
        def upsert_pending(id : String, endpoint_id : String, event_id : String, event_type : String, payload : String) : WebhookDeliveryRecord
          exec(
            <<-SQL,
              INSERT INTO webhook_deliveries (id, endpoint_id, event_id, event_type, payload, status, created_at)
              VALUES ($1, $2, $3, $4, $5, 'pending', NOW())
              ON CONFLICT (endpoint_id, event_id) DO NOTHING
            SQL
            id, endpoint_id, event_id, event_type, payload
          )
          find_by_endpoint_event(endpoint_id, event_id).not_nil!
        end

        def find_by_endpoint_event(endpoint_id : String, event_id : String) : WebhookDeliveryRecord?
          one?(
            <<-SQL,
              SELECT id, endpoint_id, event_id, event_type, status, attempt_count, response_status, last_error, delivered_at, created_at
              FROM webhook_deliveries
              WHERE endpoint_id = $1 AND event_id = $2
            SQL
            endpoint_id, event_id
          ) do |rs|
            map_delivery(rs)
          end
        end

        def mark_delivered(id : String, response_status : Int32) : Nil
          exec(
            <<-SQL,
              UPDATE webhook_deliveries
              SET status = 'delivered',
                  attempt_count = attempt_count + 1,
                  response_status = $2,
                  last_error = NULL,
                  delivered_at = NOW()
              WHERE id = $1
            SQL
            id, response_status
          )
        end

        def mark_failed(id : String, error : String, response_status : Int32?) : Nil
          exec(
            <<-SQL,
              UPDATE webhook_deliveries
              SET status = 'failed',
                  attempt_count = attempt_count + 1,
                  response_status = $2,
                  last_error = $3
              WHERE id = $1
            SQL
            id, response_status, error
          )
        end

        def list_for_endpoint(endpoint_id : String, limit : Int32 = 50) : Array(WebhookDeliveryRecord)
          many(
            <<-SQL,
              SELECT id, endpoint_id, event_id, event_type, status, attempt_count, response_status, last_error, delivered_at, created_at
              FROM webhook_deliveries
              WHERE endpoint_id = $1
              ORDER BY created_at DESC
              LIMIT $2
            SQL
            endpoint_id, limit
          ) do |rs|
            map_delivery(rs)
          end
        end

        private def map_delivery(rs : ::DB::ResultSet) : WebhookDeliveryRecord
          WebhookDeliveryRecord.new(
            id: rs.read(String),
            endpoint_id: rs.read(String),
            event_id: rs.read(String),
            event_type: rs.read(String),
            status: rs.read(String),
            attempt_count: rs.read(Int32),
            response_status: rs.read(Int32?),
            last_error: rs.read(String?),
            delivered_at: rs.read(Time?),
            created_at: rs.read(Time)
          )
        end
      end
    end
  end
end
