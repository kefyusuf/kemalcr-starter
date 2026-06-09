require "digest/sha256"
require "uuid"

module KemalcrStarter
  module Infrastructure
    module Crypto
      class ApiKeySecretHasher
        PREFIX_LENGTH = 12

        def initialize(@pepper : String)
        end

        def generate_secret : String
          "kma_#{random_hex}#{random_hex}"
        end

        def prefix(secret : String) : String
          secret[0, PREFIX_LENGTH]
        end

        def hash(secret : String) : String
          Digest::SHA256.hexdigest("#{@pepper}:#{secret}")
        end

        def verify(secret : String, digest : String) : Bool
          hash(secret) == digest
        end

        private def random_hex : String
          UUID.random.to_s.gsub("-", "")
        end
      end
    end
  end
end
