require "uuid"
require "../domain_event"
require "../event_handler"

module KemalcrStarter
  module Core
    module Events
      class ApiKeyAuditHandler
        include EventHandler

        def initialize(@repository : Infrastructure::DB::AuditLogRepository)
        end

        def handle(event : DomainEvent) : Nil
          data = event.event_data

          case event.event_type
          when "api_key.created"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: nil,
              action: "api_key.created",
              resource_type: "api_key",
              resource_id: event.aggregate_id,
              new_value: data.to_json
            )
          when "api_key.revoked"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: nil,
              action: "api_key.revoked",
              resource_type: "api_key",
              resource_id: event.aggregate_id,
              old_value: data.to_json
            )
          end
        end
      end
    end
  end
end
