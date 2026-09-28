module KemalcrStarter
  module Modules
    module Products
      class ProductCreated < Core::Events::DomainEvent
        getter event_type : String = "product.created"
        getter aggregate_type : String = "product"
        getter organization_id : String
        getter sku : String
        getter name : String

        def initialize(@aggregate_id : String, @organization_id : String, @sku : String, @name : String, correlation_id : String? = nil)
          super(event_type: "product.created", aggregate_type: "product",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id, sku: @sku, name: @name}.to_json)
        end
      end

      class ProductUpdated < Core::Events::DomainEvent
        getter event_type : String = "product.updated"
        getter aggregate_type : String = "product"
        getter organization_id : String
        getter name : String

        def initialize(@aggregate_id : String, @organization_id : String, @name : String, correlation_id : String? = nil)
          super(event_type: "product.updated", aggregate_type: "product",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id, name: @name}.to_json)
        end
      end

      class ProductDeleted < Core::Events::DomainEvent
        getter event_type : String = "product.deleted"
        getter aggregate_type : String = "product"
        getter organization_id : String

        def initialize(@aggregate_id : String, @organization_id : String, correlation_id : String? = nil)
          super(event_type: "product.deleted", aggregate_type: "product",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id}.to_json)
        end
      end
    end
  end
end
