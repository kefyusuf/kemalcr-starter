require "uuid"
require "../domain_event"
require "../event_handler"

module KemalcrStarter
  module Core
    module Events
      class OrganizationAuditHandler
        include EventHandler

        def initialize(@repository : Infrastructure::DB::AuditLogRepository)
        end

        def handle(event : DomainEvent) : Nil
          data = event.event_data

          case event.event_type
          when "organization.created"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: data["owner_id"]?.try(&.as_s),
              action: "organization.created",
              resource_type: "organization",
              resource_id: event.aggregate_id,
              new_value: data.to_json
            )
          when "organization.updated"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: nil,
              action: "organization.updated",
              resource_type: "organization",
              resource_id: event.aggregate_id
            )
          end
        end
      end
    end
  end
end
