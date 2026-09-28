require "http/client"
require "uri"

module KemalcrStarter
  module Infrastructure
    module Email
      # Minimal SMTP adapter. TLS/STARTTLS and auth are intentionally narrow —
      # replace via App.install_email_adapter when a richer provider is needed.
      class SmtpEmailAdapter < EmailAdapter
        def initialize(@host : String, @port : Int32, @username : String?, @password : String?, @from : String)
        end

        def deliver(message : EmailMessage) : Nil
          from = message.from || @from
          socket = TCPSocket.new(@host, @port)
          begin
            smtp = SmtpSession.new(socket, @host, @username, @password)
            smtp.helo
            smtp.auth if @username && @password
            smtp.mail(from)
            smtp.rcpt(message.to)
            smtp.data(from, message.to, message.subject, message.body)
            smtp.quit
          ensure
            socket.close rescue nil
          end
        end

        private class SmtpSession
          def initialize(@socket : TCPSocket, @host : String, @username : String?, @password : String?)
          end

          def helo : Nil
            expect 220
            write "EHLO #{@host}"
            expect 250
          end

          def auth : Nil
            write "AUTH LOGIN"
            expect 334
            write Base64.strict_encode(@username.not_nil!)
            expect 334
            write Base64.strict_encode(@password.not_nil!)
            expect 235
          end

          def mail(from : String) : Nil
            write "MAIL FROM:<#{from}>"
            expect 250
          end

          def rcpt(to : String) : Nil
            write "RCPT TO:<#{to}>"
            expect 250
          end

          def data(from : String, to : String, subject : String, body : String) : Nil
            write "DATA"
            expect 354
            write "From: #{from}"
            write "To: #{to}"
            write "Subject: #{subject}"
            write ""
            body.each_line { |line| write(line.starts_with?(".") ? ".#{line}" : line) }
            write "."
            expect 250
          end

          def quit : Nil
            write "QUIT"
            expect 221
          rescue
          end

          private def write(line : String) : Nil
            @socket.print "#{line}\r\n"
            @socket.flush
          end

          private def expect(code : Int32) : Nil
            response = @socket.gets || raise IO::Error.new("SMTP connection closed")
            unless response.starts_with?(code.to_s)
              raise IO::Error.new("SMTP unexpected response: #{response}")
            end
          end
        end
      end
    end
  end
end
