module KemalcrStarter
  module Core
    module Http
      record RequestContext,
        request_id : String,
        actor_id : String? = nil,
        organization_id : String? = nil,
        session_id : String? = nil,
        api_key_id : String? = nil
    end
  end
end
