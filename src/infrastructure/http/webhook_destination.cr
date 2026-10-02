require "socket"
require "uri"

module KemalcrStarter
  module Infrastructure
    module Http
      class WebhookResolver
        def resolve(host : String, port : Int32) : Array(Socket::IPAddress)
          Socket::Addrinfo.tcp(host, port).map(&.ip_address)
        end
      end

      class WebhookDestination
        def initialize(@settings : Core::Config::Settings, @resolver : WebhookResolver = WebhookResolver.new)
        end

        def validate!(url : String) : URI
          uri = URI.parse(url.strip)
          host = uri.hostname
          reject! unless host && !host.empty?
          reject! if uri.user || uri.password || uri.fragment
          local = test_loopback? && (host == "localhost" || literal_loopback?(host))
          reject! unless (uri.scheme == "https" && (uri.port.nil? || uri.port == 443)) ||
                         (local && (uri.scheme == "http" || uri.scheme == "https"))
          reject! if uri.port.try { |port| port < 1 || port > 65535 }

          if address = literal_address(host, uri.port || 443)
            reject! unless allowed?(address)
          else
            reject! unless local || valid_hostname?(host)
          end
          uri
        rescue URI::Error
          reject!
        end

        def resolve!(uri : URI) : Socket::IPAddress
          host = uri.hostname.not_nil!
          port = uri.port || (uri.scheme == "https" ? 443 : 80)
          addresses = @resolver.resolve(host, port)
          reject! if addresses.empty? || addresses.any? { |address| !allowed?(address) }
          addresses.first
        end

        private def test_loopback? : Bool
          @settings.environment == "test" && @settings.webhook_allow_test_loopback
        end

        private def literal_loopback?(host : String) : Bool
          literal_address(host, 443).try(&.loopback?) || false
        end

        private def literal_address(host : String, port : Int32) : Socket::IPAddress?
          return nil unless Socket::IPAddress.valid?(host)
          Socket::IPAddress.new(host, port)
        end

        private def valid_hostname?(host : String) : Bool
          return false if host.bytesize > 253 || host.ends_with?('.')
          labels = host.split('.')
          return false if labels.size < 2 || !labels.last.matches?(/\A[a-zA-Z][a-zA-Z0-9-]*\z/)
          labels.all? { |label| label.bytesize <= 63 && label.matches?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\z/) }
        end

        private def allowed?(address : Socket::IPAddress) : Bool
          return true if test_loopback? && address.loopback?
          return false if address.loopback? || address.private? || address.link_local? || address.unspecified?
          if fields = Socket::IPAddress.parse_v4_fields?(address.address)
            a, b, c, d = fields
            return false if a == 0 || a >= 224 || a == 127 || a == 10
            return false if a == 100 && (64..127).includes?(b)
            return false if a == 169 && b == 254
            return false if a == 172 && (16..31).includes?(b)
            return false if a == 168 && b == 63 && c == 129 && d == 16
            return false if a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)) || (b == 88 && c == 99))
            return false if a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))
            return false if a == 203 && b == 0 && c == 113
            true
          elsif fields = Socket::IPAddress.parse_v6_fields?(address.address)
            a, b = fields[0], fields[1]
            return false unless (a & 0xe000) == 0x2000
            return false if a == 0x2001 && (b < 0x0200 || b == 0x0db8)
            return false if a == 0x2002 || (a == 0x3fff && b < 0x1000)
            true
          else
            false
          end
        end

        private def reject! : NoReturn
          raise Core::Errors::ValidationError.new("Webhook destination is not permitted.")
        end
      end
    end
  end
end
