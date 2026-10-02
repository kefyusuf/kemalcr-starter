require "http/server"
require "openssl/hmac"
require "json"

module KemalcrStarter
  record ReceivedHook, headers : HTTP::Headers, body : String do
    def signature : String?
      headers["X-Webhook-Signature"]?
    end
  end

  class WebhookReceiver
    getter requests : Array(ReceivedHook)
    getter secret : String
    property response_status : Int32 = 200
    property response_headers : HTTP::Headers = HTTP::Headers.new

    @port : Int32 = 0
    @server : HTTP::Server?

    def initialize(@secret : String)
      @requests = [] of ReceivedHook
      @channel = Channel(ReceivedHook).new(8)
    end

    def start(host : String = "127.0.0.1") : Int32
      server = HTTP::Server.new do |context|
        payload = context.request.body.try(&.gets_to_end) || ""
        entry = ReceivedHook.new(headers: context.request.headers.dup, body: payload)
        @requests << entry
        @channel.send(entry)
        context.response.status_code = @response_status
        @response_headers.each { |name, value| context.response.headers[name] = value }
        context.response.print "ok"
      end

      @server = server
      address = server.bind_tcp(host, 0)
      @port = address.port
      spawn { server.listen }
      @port
    end

    def stop : Nil
      @server.try(&.close)
    end

    def wait_for_request(timeout : Time::Span = 5.seconds) : ReceivedHook
      select
      when entry = @channel.receive
        entry
      when timeout(timeout)
        raise "webhook receiver timed out"
      end
    end

    def verify_signature(body : String, signature_header : String) : Bool
      expected = "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, @secret, body)}"
      signature_header == expected
    end
  end
end
