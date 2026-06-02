module KemalcrStarter
  module Modules
    module ApiKeys
      class ApiKeyCreated < Core::Events::DomainEvent
        getter event_type : String = "api_key.created"
        getter aggregate_type : String = "api_key"
        getter organization_id : String
        getter name : String

        def initialize(@aggregate_id : String, @organization_id : String, @name : String, correlation_id : String? = nil)
          super(event_type: "api_key.created", aggregate_type: "api_key",
                aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id, name: @name}.to_json)
        end
      end

      class ApiKeyRevoked < Core::Events::DomainEvent
        getter event_type : String = "api_key.revoked"
        getter aggregate_type : String = "api_key"
        getter organization_id : String

        def initialize(@aggregate_id : String, @organization_id : String, correlation_id : String? = nil)
          super(event_type: "api_key.revoked", aggregate_type: "api_key",
                aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id}.to_json)
        end
      end
    end
  end
end
