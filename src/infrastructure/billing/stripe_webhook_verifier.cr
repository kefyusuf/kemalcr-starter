require "openssl/hmac"

module KemalcrStarter
  module Infrastructure
    module Billing
      # Verifies Stripe `Stripe-Signature` header (t=...,v1=...).
      # Format: signed_payload = "#{timestamp}.#{raw_body}", HMAC-SHA256 with endpoint secret.
      class StripeWebhookVerifier
        def initialize(@secret : String, @tolerance_seconds : Int32 = 300)
        end

        def verify(payload : String, signature_header : String?, now : Time = Time.utc) : Bool
          return false if signature_header.nil? || signature_header.empty?

          timestamp = nil.as(Time?)
          candidates = [] of String

          signature_header.split(",").each do |part|
            key, _, value = part.strip.partition("=")
            case key
            when "t"
              begin
                timestamp = Time.unix(value.to_i64)
              rescue ArgumentError
                return false
              end
            when "v1"
              candidates << value
            end
          end

          return false if timestamp.nil? || candidates.empty?

          age = (now - timestamp.not_nil!).abs.total_seconds
          return false if age > @tolerance_seconds

          expected = OpenSSL::HMAC.hexdigest(
            OpenSSL::Algorithm::SHA256,
            @secret,
            "#{timestamp.not_nil!.to_unix}.#{payload}"
          )

          candidates.any? { |candidate| secure_compare(candidate, expected) }
        end

        private def secure_compare(a : String, b : String) : Bool
          return false unless a.bytesize == b.bytesize

          result = 0_u8
          a.bytes.each_with_index do |byte, index|
            result |= byte ^ b.to_unsafe[index]
          end
          result == 0
        end
      end
    end
  end
end
