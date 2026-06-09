require "crypto/bcrypt/password"

module KemalcrStarter
  module Infrastructure
    module Crypto
      class PasswordHasher
        def initialize(@pepper : String, @cost : Int32)
        end

        def hash(password : String) : String
          ::Crypto::Bcrypt::Password.create(materialize(password), cost: @cost).to_s
        end

        def verify(password : String, digest : String) : Bool
          ::Crypto::Bcrypt::Password.new(digest).verify(materialize(password))
        rescue ::Crypto::Bcrypt::Error
          false
        end

        private def materialize(password : String) : String
          "#{password}#{@pepper}"
        end
      end
    end
  end
end
