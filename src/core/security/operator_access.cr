require "digest/sha256"

module KemalcrStarter
  module Core
    module Security
      module OperatorAccess
        extend self

        def authorize!(env : HTTP::Server::Context, configured_token : String?) : Nil
          supplied_token = env.request.headers["X-Operator-Token"]?
          raise Errors::UnauthorizedError.new if configured_token.nil? || configured_token.blank?
          raise Errors::UnauthorizedError.new if supplied_token.nil? || supplied_token.blank?

          expected = Digest::SHA256.digest(configured_token)
          supplied = Digest::SHA256.digest(supplied_token)
          difference = 0_u8
          expected.each_with_index do |byte, index|
            difference |= byte ^ supplied[index]
          end
          raise Errors::UnauthorizedError.new unless difference == 0
        end
      end
    end
  end
end
