module KemalcrStarter
  module Modules
    module Organizations
      class OrganizationCreated < Core::Events::DomainEvent
        getter event_type : String = "organization.created"
        getter aggregate_type : String = "organization"
        getter name : String
        getter owner_id : String

        def initialize(@aggregate_id : String, @name : String, @owner_id : String, correlation_id : String? = nil)
          super(event_type: "organization.created", aggregate_type: "organization",
                aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({name: @name, owner_id: @owner_id}.to_json)
        end
      end

      class OrganizationUpdated < Core::Events::DomainEvent
        getter event_type : String = "organization.updated"
        getter aggregate_type : String = "organization"

        def initialize(@aggregate_id : String, correlation_id : String? = nil)
          super(event_type: "organization.updated", aggregate_type: "organization",
                aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse("{}")
        end
      end

      class MembershipInvited < Core::Events::DomainEvent
        getter event_type : String = "organization.membership.invited"
        getter aggregate_type : String = "membership"
        getter organization_id : String
        getter invited_email : String
        getter role : String

        def initialize(@aggregate_id : String, @organization_id : String, @invited_email : String, @role : String, correlation_id : String? = nil)
          super(event_type: "organization.membership.invited", aggregate_type: "membership",
                aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id, invited_email: @invited_email, role: @role}.to_json)
        end
      end

      class MembershipAccepted < Core::Events::DomainEvent
        getter event_type : String = "organization.membership.accepted"
        getter aggregate_type : String = "membership"
        getter organization_id : String

        def initialize(@aggregate_id : String, @organization_id : String, correlation_id : String? = nil)
          super(event_type: "organization.membership.accepted", aggregate_type: "membership",
                aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id}.to_json)
        end
      end

      class MembershipRevoked < Core::Events::DomainEvent
        getter event_type : String = "organization.membership.revoked"
        getter aggregate_type : String = "membership"
        getter organization_id : String

        def initialize(@aggregate_id : String, @organization_id : String, correlation_id : String? = nil)
          super(event_type: "organization.membership.revoked", aggregate_type: "membership",
                aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({organization_id: @organization_id}.to_json)
        end
      end
    end
  end
end
