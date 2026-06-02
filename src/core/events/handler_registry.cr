require "./events"

module KemalcrStarter
  module Core
    module Events
      class HandlerRegistry
        @handlers = {} of String => Array(EventHandler)

        def register(event_type : String, handler : EventHandler) : Nil
          @handlers[event_type] ||= [] of EventHandler
          @handlers[event_type].not_nil! << handler
        end

        def handlers_for(event_type : String) : Array(EventHandler)
          @handlers.fetch(event_type, [] of EventHandler)
        end

        def clear : Nil
          @handlers.clear
        end
      end
    end
  end
end
