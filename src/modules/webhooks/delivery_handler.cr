module KemalcrStarter
  module Modules
    module Webhooks
      class DeliveryHandler
        include Core::Events::EventHandler

        def initialize(@service : WebhookService)
        end

        def handle(event : Core::Events::DomainEvent) : Nil
          @service.dispatch_event(event)
        end
      end
    end
  end
end
