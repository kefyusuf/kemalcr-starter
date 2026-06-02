require "spec"
require "../../spec_helper"
require "../../support/event_helpers"

class TestHandler
  include KemalcrStarter::Core::Events::EventHandler

  getter handled_events : Array(KemalcrStarter::Core::Events::DomainEvent) = [] of KemalcrStarter::Core::Events::DomainEvent
  getter handle_count : Int32 = 0

  def handle(event : KemalcrStarter::Core::Events::DomainEvent) : Nil
    @handled_events << event
    @handle_count += 1
  end
end

describe KemalcrStarter::Core::Events::HandlerRegistry do
  describe "#register" do
    it "registers a handler for an event type" do
      r = KemalcrStarter::Core::Events::HandlerRegistry.new
      handler = TestHandler.new
      r.register("test.event", handler)
      handlers = r.handlers_for("test.event")
      handlers.size.should eq(1)
      handlers.first.should be(handler)
    end

    it "allows multiple handlers for the same event type" do
      r = KemalcrStarter::Core::Events::HandlerRegistry.new
      handler1 = TestHandler.new
      handler2 = TestHandler.new
      r.register("test.event", handler1)
      r.register("test.event", handler2)
      handlers = r.handlers_for("test.event")
      handlers.size.should eq(2)
    end

    it "registers handlers for different event types independently" do
      r = KemalcrStarter::Core::Events::HandlerRegistry.new
      handler1 = TestHandler.new
      handler2 = TestHandler.new
      r.register("event.a", handler1)
      r.register("event.b", handler2)
      r.handlers_for("event.a").size.should eq(1)
      r.handlers_for("event.b").size.should eq(1)
    end
  end

  describe "#handlers_for" do
    it "returns empty array for unknown event type" do
      r = KemalcrStarter::Core::Events::HandlerRegistry.new
      r.handlers_for("unknown.event").should be_empty
    end

    it "does not mutate when fetching unknown event type" do
      r = KemalcrStarter::Core::Events::HandlerRegistry.new
      r.handlers_for("unknown.event")
      r.handlers_for("unknown.event").should be_empty
    end
  end

  describe "#clear" do
    it "removes all registered handlers" do
      r = KemalcrStarter::Core::Events::HandlerRegistry.new
      handler = TestHandler.new
      r.register("test.event", handler)
      r.clear
      r.handlers_for("test.event").should be_empty
    end
  end

  describe "App.boot registration pattern" do
    it "registers and resolves handlers through App.handler_registry" do
      handler = TestHandler.new
      KemalcrStarter::App.handler_registry.register("test.event", handler)
      handlers = KemalcrStarter::App.handler_registry.handlers_for("test.event")
      handlers.size.should eq(1)
      handlers.first.should be(handler)
    end
  end
end
