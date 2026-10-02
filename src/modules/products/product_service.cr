require "uuid"
require "json"

module KemalcrStarter
  module Modules
    module Products
      record ProductView,
        id : String,
        organization_id : String,
        sku : String,
        name : String,
        description : String?,
        price_cents : Int32,
        currency : String,
        status : String,
        created_at : String,
        updated_at : String do
        include JSON::Serializable
      end

      class ProductService
        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database,
                       @event_repository : Infrastructure::DB::OutboxEventRepository? = nil)
          @event_repository ||= Infrastructure::DB::OutboxEventRepository.new(@database)
          @repository = Infrastructure::DB::ProductRepository.new(@database)
          @rbac_service = Core::Rbac::AuthorizationService.new(
            Infrastructure::DB::RbacRepository.new(@database)
          )
        end

        def create_product(actor_id : String, organization_id : String, sku : String, name : String,
                           description : String?, price_cents : Int32, currency : String) : ProductView
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::ProductManage)
          raise Core::Errors::ValidationError.new("SKU is required.") if sku.strip.empty?
          raise Core::Errors::ValidationError.new("Name is required.") if name.strip.empty?
          raise Core::Errors::ValidationError.new("Price must be >= 0.") if price_cents < 0

          id = "prd_#{UUID.random}"
          record = @database.transaction do |txn|
            repository = Infrastructure::DB::ProductRepository.new(txn.connection)
            created = repository.create(
              id: id,
              organization_id: organization_id,
              sku: sku.strip,
              name: name.strip,
              description: description,
              price_cents: price_cents,
              currency: currency.strip.upcase,
              created_by: actor_id
            )
            publish_event(ProductCreated.new(created.id, organization_id, created.sku, created.name), txn.connection)
            created
          end.not_nil!
          view(record)
        end

        def list_products(actor_id : String, organization_id : String, status : String? = nil,
                          limit : Int32 = 50, offset : Int32 = 0) : Array(ProductView)
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::ProductList)
          @repository.list_for_organization(organization_id, status, limit, offset).map { |r| view(r) }
        end

        def get_product(actor_id : String, organization_id : String, product_id : String) : ProductView?
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::ProductList)
          record = @repository.find(product_id)
          return nil unless record
          return nil unless record.organization_id == organization_id

          view(record)
        end

        def update_product(actor_id : String, organization_id : String, product_id : String,
                           name : String?, description : String?, price_cents : Int32?, status : String?) : ProductView?
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::ProductManage)
          updated = @database.transaction do |txn|
            repository = Infrastructure::DB::ProductRepository.new(txn.connection)
            existing = repository.find(product_id)
            next nil unless existing && existing.organization_id == organization_id

            record = repository.update(product_id, name, description, price_cents, status)
            publish_event(ProductUpdated.new(record.id, organization_id, record.name), txn.connection) if record
            record
          end
          return nil unless updated

          view(updated)
        end

        def delete_product(actor_id : String, organization_id : String, product_id : String) : Bool
          @rbac_service.authorize!(actor_id, organization_id, Core::Rbac::Permission::ProductManage)
          @database.transaction do |txn|
            repository = Infrastructure::DB::ProductRepository.new(txn.connection)
            existing = repository.find(product_id)
            next false unless existing && existing.organization_id == organization_id

            deleted = repository.delete(product_id)
            publish_event(ProductDeleted.new(product_id, organization_id), txn.connection) if deleted
            deleted
          end || false
        end

        private def view(record : Infrastructure::DB::ProductRecord) : ProductView
          ProductView.new(
            id: record.id,
            organization_id: record.organization_id,
            sku: record.sku,
            name: record.name,
            description: record.description,
            price_cents: record.price_cents,
            currency: record.currency,
            status: record.status,
            created_at: record.created_at.to_rfc3339,
            updated_at: record.updated_at.to_rfc3339
          )
        end

        private def publish_event(event : Core::Events::DomainEvent, connection : ::DB::Connection) : Nil
          @event_repository.not_nil!.create(event, connection: connection)
        end
      end
    end
  end
end
