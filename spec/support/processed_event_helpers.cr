require "../../../src/kemalcr_starter"

class TestProcessedEventRepository
  getter processed : Array({String, String}) = [] of {String, String}

  def already_processed?(event_id : String, handler_name : String) : Bool
    processed.any? { |(eid, hn)| eid == event_id && hn == handler_name }
  end

  def mark_processed(event_id : String, handler_name : String) : Nil
    processed << {event_id, handler_name}
  end
end
