require "redis"

module KemalcrStarter
  module Infrastructure
    module Outbox
      class OutboxPublisher
        getter stats : PublisherStats
        getter running : Bool

        def initialize(@repository : DB::OutboxEventRepository,
                       @handler_registry : Core::Events::HandlerRegistry,
                       @poll_interval : Time::Span = 1.seconds,
                       @batch_size : Int32 = 50,
                       @max_retries : Int32 = 5,
                       @redis_url : String? = nil)
          @stats = PublisherStats.new
          @running = false
          @fiber = nil.as(Fiber?)
          @subscriber_fiber = nil.as(Fiber?)
          @notifications = Channel(String).new
          @mutex = Mutex.new
        end

        def start : Nil
          @mutex.synchronize do
            return if @running
            @running = true
          end

          @fiber = spawn do
            Log.info { "Outbox publisher started (interval: #{@poll_interval}, batch: #{@batch_size})" }
            while running?
              begin
                process_batch
              rescue ex
                Log.error(exception: ex) { "Outbox publisher: batch error" }
              end
              sleep @poll_interval
            end
            Log.info { "Outbox publisher stopped" }
          end

          start_redis_subscriber if @redis_url
        end

        def stop : Nil
          @mutex.synchronize do
            @running = false
          end
        end

        def running? : Bool
          @mutex.synchronize { @running }
        end

        def process_now! : Int32
          process_batch
        end

        private def process_batch : Int32
          @repository.reclaim_stale_in_progress
          events = @repository.next_batch(@batch_size)
          @stats.record_poll

          events.each do |event|
            dispatch_event(event)
          end

          events.size
        end

        private def dispatch_event(event : DB::OutboxEventRecord) : Nil
          handlers = @handler_registry.handlers_for(event.event_type)
          if handlers.empty?
            Log.warn { "No handlers registered for event_type=#{event.event_type} event_id=#{event.id}" }
            @repository.mark_dispatched(event)
            return
          end

          reconstituted = ReconstitutedEvent.new(event)

          handlers.each do |handler|
            begin
              handler.handle(reconstituted)
            rescue ex
              Log.error(exception: ex) { "Handler failed event_id=#{event.id} handler=#{handler.class.name}" }
              next_attempt = event.attempts + 1
              if next_attempt > @max_retries
                @stats.increment_dead_letter if @repository.move_to_dead_letter(event, ex.message)
              else
                backoff = (2 ** (next_attempt - 1)).seconds
                @stats.increment_failed if @repository.increment_retry(event, ex.message, backoff.seconds.to_i)
              end
              return
            end
          end

          @stats.increment_dispatched if @repository.mark_dispatched(event)
        rescue ex
          @stats.increment_failed
          Log.error(exception: ex) { "Outbox publisher: dispatch error event_id=#{event.id}" }
        end

        private def start_redis_subscriber : Nil
          @subscriber_fiber = spawn do
            begin
              redis = ::Redis::Client.new(URI.parse(@redis_url.not_nil!))
              redis.subscribe("events:new") do |subscription, _conn|
                subscription.on_message do |channel, message|
                  @stats.record_poll
                  process_batch
                end
              end
            rescue ex
              Log.warn(exception: ex) { "Redis subscriber: connection failed, falling back to polling" }
            end
          end
        end
      end

      private class ReconstitutedEvent < KemalcrStarter::Core::Events::DomainEvent
        getter event_type : String
        getter aggregate_type : String
        getter event_data : JSON::Any

        def initialize(record : DB::OutboxEventRecord)
          @event_type = record.event_type
          @aggregate_type = record.aggregate_type
          @event_data = JSON.parse(record.event_data)
          @stored_event_id = record.id
          @stored_created_at = record.created_at
          super(
            event_type: record.event_type,
            aggregate_type: record.aggregate_type,
            aggregate_id: record.aggregate_id,
            correlation_id: record.correlation_id,
            causation_id: record.causation_id
          )
        end

        def event_data : JSON::Any
          @event_data
        end

        def event_id : String
          @stored_event_id
        end

        def timestamp : Time
          @stored_created_at
        end
      end
    end
  end
end
