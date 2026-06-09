require "uuid"
require "../domain_event"
require "../event_handler"

module KemalcrStarter
  module Core
    module Events
      class MembershipAuditHandler
        include EventHandler

        def initialize(@repository : Infrastructure::DB::AuditLogRepository)
        end

        def handle(event : DomainEvent) : Nil
          data = event.event_data

          case event.event_type
          when "organization.membership.invited"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: nil,
              action: "membership.invited",
              resource_type: "membership",
              resource_id: event.aggregate_id,
              new_value: data.to_json
            )
            simulate_email(data["invited_email"]?.try(&.as_s), event.aggregate_id)
          when "organization.membership.accepted"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: nil,
              action: "membership.accepted",
              resource_type: "membership",
              resource_id: event.aggregate_id,
              new_value: data.to_json
            )
          when "organization.membership.revoked"
            @repository.create(
              id: "aud_#{UUID.random}",
              event_id: event.event_id,
              actor_id: nil,
              action: "membership.revoked",
              resource_type: "membership",
              resource_id: event.aggregate_id,
              old_value: data.to_json
            )
          end
        end

        private def simulate_email(email : String?, organization_id : String) : Nil
          return unless email

          Log.info { "email_notification to=#{email} template=organization_invitation org_id=#{organization_id}" }
        end
      end
    end
  end
end
