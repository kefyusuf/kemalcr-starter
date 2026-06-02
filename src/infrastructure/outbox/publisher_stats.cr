module KemalcrStarter
  module Infrastructure
    module Outbox
      class PublisherStats
        getter dispatched : Int32 = 0
        getter failed : Int32 = 0
        getter dead_letter : Int32 = 0
        getter last_poll_at : Time?

        def increment_dispatched : Nil
          @dispatched += 1
        end

        def increment_failed : Nil
          @failed += 1
        end

        def increment_dead_letter : Nil
          @dead_letter += 1
        end

        def record_poll : Nil
          @last_poll_at = Time.utc
        end

        def to_s : String
          "dispatched=#{@dispatched} failed=#{@failed} dead_letter=#{@dead_letter} last_poll=#{@last_poll_at}"
        end
      end
    end
  end
end
