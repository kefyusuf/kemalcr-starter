require "uuid"
require "../domain_event"
require "../event_handler"

module KemalcrStarter
  module Core
    module Events
      class UserAuditHandler
        include EventHandler

        def initialize(@repository : Infrastructure::DB::AuditLogRepository)
        end

        def handle(event : DomainEvent) : Nil
          data = event.event_data

          case event.event_type
          when "identity.user.created"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: event.aggregate_id,
              action: "user.created",
              resource_type: "user",
              resource_id: event.aggregate_id,
              new_value: data.to_json
            )
          when "identity.user.logged_in"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: event.aggregate_id,
              action: "user.logged_in",
              resource_type: "user",
              resource_id: event.aggregate_id
            )
          when "identity.user.logged_out"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: event.aggregate_id,
              action: "user.logged_out",
              resource_type: "user",
              resource_id: event.aggregate_id
            )
          when "identity.session.revoked"
            session_id = data["session_id"]?.try(&.as_s)
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: event.aggregate_id,
              action: "session.revoked",
              resource_type: "session",
              resource_id: session_id || event.aggregate_id,
              new_value: data.to_json
            )
          end
        end
      end
    end
  end
end
