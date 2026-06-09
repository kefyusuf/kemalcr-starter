require "../../src/kemalcr_starter"

class TestOrganizationCreated < KemalcrStarter::Core::Events::DomainEvent
  getter event_type : String = "test.organization.created"
  getter aggregate_type : String = "organization"
  getter name : String
  getter owner_id : String

  def initialize(@aggregate_id : String, @name : String, @owner_id : String,
                 correlation_id : String? = nil, causation_id : String? = nil)
    super(event_type: "test.organization.created", aggregate_type: "organization",
      aggregate_id: @aggregate_id, correlation_id: correlation_id,
      causation_id: causation_id)
  end

  def event_data : JSON::Any
    JSON.parse({name: @name, owner_id: @owner_id}.to_json)
  end
end

class TestUserLoggedIn < KemalcrStarter::Core::Events::DomainEvent
  getter event_type : String = "test.user.logged_in"
  getter aggregate_type : String = "user"
  getter email : String

  def initialize(@aggregate_id : String, @email : String,
                 correlation_id : String? = nil, causation_id : String? = nil)
    super(event_type: "test.user.logged_in", aggregate_type: "user",
      aggregate_id: @aggregate_id, correlation_id: correlation_id,
      causation_id: causation_id)
  end

  def event_data : JSON::Any
    JSON.parse({email: @email}.to_json)
  end
end

class TestApiKeyRevoked < KemalcrStarter::Core::Events::DomainEvent
  getter event_type : String = "test.api_key.revoked"
  getter aggregate_type : String = "api_key"
  getter key_prefix : String

  def initialize(@aggregate_id : String, @key_prefix : String,
                 correlation_id : String? = nil, causation_id : String? = nil)
    super(event_type: "test.api_key.revoked", aggregate_type: "api_key",
      aggregate_id: @aggregate_id, correlation_id: correlation_id,
      causation_id: causation_id)
  end

  def event_data : JSON::Any
    JSON.parse({key_prefix: @key_prefix}.to_json)
  end
end
