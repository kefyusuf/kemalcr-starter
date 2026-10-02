require "json"
require "uuid"

module KemalcrStarter
  module Core
    module Events
      abstract class DomainEvent
        getter event_id : String
        getter event_type : String
        getter aggregate_type : String
        getter aggregate_id : String
        getter timestamp : Time
        getter correlation_id : String?
        getter causation_id : String?

        abstract def event_data : JSON::Any

        def initialize(*,
                       @event_type : String,
                       @aggregate_type : String,
                       @aggregate_id : String,
                       @correlation_id : String? = nil,
                       @causation_id : String? = nil,
                       organization_id : String? = nil)
          @tenant_organization_id = organization_id
          @event_id = UUID.random.to_s
          @timestamp = Time.utc
        end

        def organization_id : String?
          @tenant_organization_id
        end

        def to_json : String
          JSON.build do |json|
            json.object do
              json.field "event_id", event_id
              json.field "event_type", event_type
              json.field "aggregate_type", aggregate_type
              json.field "aggregate_id", aggregate_id
              json.field "organization_id", organization_id
              json.field "timestamp", timestamp.to_rfc3339
              json.field "correlation_id", correlation_id
              json.field "causation_id", causation_id
              json.field "data", event_data
            end
          end
        end

        def self.from_json(json : String) : NamedTuple(
          event_id: String,
          event_type: String,
          aggregate_type: String,
          aggregate_id: String,
          organization_id: String?,
          timestamp: String,
          correlation_id: String?,
          causation_id: String?,
          data: JSON::Any)
          parsed = JSON.parse(json).as_h
          {
            event_id:        parsed["event_id"].as_s,
            event_type:      parsed["event_type"].as_s,
            aggregate_type:  parsed["aggregate_type"].as_s,
            aggregate_id:    parsed["aggregate_id"].as_s,
            organization_id: parsed["organization_id"]?.try(&.as_s?),
            timestamp:       parsed["timestamp"].as_s,
            correlation_id:  parsed["correlation_id"]?.try(&.as_s),
            causation_id:    parsed["causation_id"]?.try(&.as_s),
            data:            parsed["data"],
          }
        end
      end
    end
  end
end
