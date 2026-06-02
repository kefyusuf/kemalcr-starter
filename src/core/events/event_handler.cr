module KemalcrStarter
  module Core
    module Events
      module EventHandler
        abstract def handle(event : DomainEvent) : Nil
      end
    end
  end
end
