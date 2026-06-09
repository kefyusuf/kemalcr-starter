module KemalcrStarter
  module Core
    module Errors
      abstract class ApiError < Exception
        getter code : String
        getter status_code : Int32
        getter details : Hash(String, String)

        def initialize(@code : String, message : String, @status_code : Int32, @details : Hash(String, String) = Hash(String, String).new)
          super(message)
        end
      end

      class UnauthorizedError < ApiError
        def initialize(message : String = "Authentication failed.", details : Hash(String, String) = Hash(String, String).new)
          super("AUTH_UNAUTHORIZED", message, 401, details)
        end
      end

      class ForbiddenError < ApiError
        def initialize(message : String = "Access to this resource is forbidden.", details : Hash(String, String) = Hash(String, String).new)
          super("AUTH_FORBIDDEN", message, 403, details)
        end
      end

      class ValidationError < ApiError
        def initialize(message : String = "Request validation failed.", details : Hash(String, String) = Hash(String, String).new)
          super("VALIDATION_ERROR", message, 422, details)
        end
      end

      class ConflictError < ApiError
        def initialize(message : String = "Request conflict detected.", details : Hash(String, String) = Hash(String, String).new)
          super("REQUEST_CONFLICT", message, 409, details)
        end
      end

      class TooManyRequestsError < ApiError
        def initialize(message : String = "Too many requests.", details : Hash(String, String) = Hash(String, String).new)
          super("RATE_LIMITED", message, 429, details)
        end
      end
    end
  end
end
