require "digest/sha256"

module KemalcrStarter
  module Infrastructure
    module Crypto
      class TokenFingerprint
        def initialize(@pepper : String)
        end

        def digest(token : String) : String
          Digest::SHA256.hexdigest("#{token}:#{@pepper}")
        end
      end
    end
  end
end
