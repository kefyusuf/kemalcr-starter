module KemalcrStarter
  module Infrastructure
    module Email
      record EmailMessage,
        to : String,
        subject : String,
        body : String,
        from : String? = nil

      # Outbound mail port. Swap implementations via App.install_email_adapter.
      abstract class EmailAdapter
        abstract def deliver(message : EmailMessage) : Nil

        def deliver(*, to : String, subject : String, body : String, from : String? = nil) : Nil
          deliver(EmailMessage.new(to: to, subject: subject, body: body, from: from))
        end
      end
    end
  end
end
