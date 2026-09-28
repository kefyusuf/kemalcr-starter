module KemalcrStarter
  module Infrastructure
    module Email
      # Default adapter: logs instead of sending. Safe for tests and local dev.
      class ConsoleEmailAdapter < EmailAdapter
        def deliver(message : EmailMessage) : Nil
          Log.info { "email to=#{message.to} subject=#{message.subject} from=#{message.from || "default"}" }
          Log.info { "email_body #{message.body}" }
        end
      end
    end
  end
end
