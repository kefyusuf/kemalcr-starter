module KemalcrStarter
  module Modules
    module Identity
      class UserCreated < Core::Events::DomainEvent
        getter event_type : String = "identity.user.created"
        getter aggregate_type : String = "user"
        getter email : String

        def initialize(@aggregate_id : String, @email : String, correlation_id : String? = nil)
          super(event_type: "identity.user.created", aggregate_type: "user",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({email: @email}.to_json)
        end
      end

      class UserLoggedIn < Core::Events::DomainEvent
        getter event_type : String = "identity.user.logged_in"
        getter aggregate_type : String = "user"

        def initialize(@aggregate_id : String, correlation_id : String? = nil)
          super(event_type: "identity.user.logged_in", aggregate_type: "user",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse("{}")
        end
      end

      class UserLoggedOut < Core::Events::DomainEvent
        getter event_type : String = "identity.user.logged_out"
        getter aggregate_type : String = "user"

        def initialize(@aggregate_id : String, correlation_id : String? = nil)
          super(event_type: "identity.user.logged_out", aggregate_type: "user",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse("{}")
        end
      end

      class SessionRevoked < Core::Events::DomainEvent
        getter event_type : String = "identity.session.revoked"
        getter aggregate_type : String = "session"
        getter session_id : String

        def initialize(@aggregate_id : String, @session_id : String, correlation_id : String? = nil)
          super(event_type: "identity.session.revoked", aggregate_type: "session",
            aggregate_id: @aggregate_id, correlation_id: correlation_id)
        end

        def event_data : JSON::Any
          JSON.parse({session_id: @session_id}.to_json)
        end
      end
    end
  end
end
