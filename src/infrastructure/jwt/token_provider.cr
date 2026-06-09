require "jwt"
require "uuid"

module KemalcrStarter
  module Infrastructure
    module Jwt
      struct TokenPairResponse
        include JSON::Serializable

        getter access_token : String
        getter refresh_token : String
        getter token_type : String
        getter expires_in : Int32

        def initialize(@access_token : String, @refresh_token : String, @expires_in : Int32, @token_type : String = "Bearer")
        end
      end

      record AccessTokenClaims,
        user_id : String,
        session_id : String,
        active_organization_id : String?

      record RefreshTokenClaims,
        user_id : String,
        session_id : String,
        session_family_id : String,
        token_id : String,
        expires_at : Time

      record IssuedTokenPair,
        access_token : String,
        refresh_token : String,
        refresh_token_id : String,
        refresh_expires_at : Time,
        access_expires_in : Int32 do
        def to_response : TokenPairResponse
          TokenPairResponse.new(
            access_token: access_token,
            refresh_token: refresh_token,
            expires_in: access_expires_in
          )
        end
      end

      class TokenProvider
        ALGORITHM = JWT::Algorithm::HS256

        def initialize(@secret : String, @issuer : String, @access_ttl_minutes : Int32, @refresh_ttl_days : Int32)
        end

        def issue_token_pair(user_id : String, session_id : String, session_family_id : String, active_organization_id : String? = nil, now : Time = Time.utc) : IssuedTokenPair
          access_expires_at = now + @access_ttl_minutes.minutes
          refresh_expires_at = now + @refresh_ttl_days.days
          refresh_token_id = "rtk_#{UUID.random}"

          access_payload = Hash(String, String | Int64).new
          access_payload["sub"] = user_id
          access_payload["sid"] = session_id
          access_payload["iss"] = @issuer
          access_payload["iat"] = now.to_unix
          access_payload["exp"] = access_expires_at.to_unix
          access_payload["token_use"] = "access"
          access_payload["org"] = active_organization_id.not_nil! if active_organization_id

          refresh_payload = {
            "sub"       => user_id,
            "sid"       => session_id,
            "fam"       => session_family_id,
            "jti"       => refresh_token_id,
            "iss"       => @issuer,
            "iat"       => now.to_unix,
            "exp"       => refresh_expires_at.to_unix,
            "token_use" => "refresh",
          }

          IssuedTokenPair.new(
            access_token: JWT.encode(access_payload, @secret, ALGORITHM),
            refresh_token: JWT.encode(refresh_payload, @secret, ALGORITHM),
            refresh_token_id: refresh_token_id,
            refresh_expires_at: refresh_expires_at,
            access_expires_in: (@access_ttl_minutes * 60).to_i
          )
        end

        def decode_access_token(token : String) : AccessTokenClaims
          payload, _header = JWT.decode(token, @secret, ALGORITHM, iss: @issuer)
          token_use = payload["token_use"]?.try(&.as_s?)
          raise JWT::VerificationError.new("Unexpected token type") unless token_use == "access"

          AccessTokenClaims.new(
            user_id: payload["sub"].as_s,
            session_id: payload["sid"].as_s,
            active_organization_id: payload["org"]?.try(&.as_s?)
          )
        rescue JWT::Error | KeyError | TypeCastError
          raise Core::Errors::UnauthorizedError.new
        end

        def decode_refresh_token(token : String) : RefreshTokenClaims
          payload, _header = JWT.decode(token, @secret, ALGORITHM, iss: @issuer)
          token_use = payload["token_use"]?.try(&.as_s?)
          raise JWT::VerificationError.new("Unexpected token type") unless token_use == "refresh"

          RefreshTokenClaims.new(
            user_id: payload["sub"].as_s,
            session_id: payload["sid"].as_s,
            session_family_id: payload["fam"].as_s,
            token_id: payload["jti"].as_s,
            expires_at: Time.unix(payload["exp"].as_i64)
          )
        rescue JWT::Error | KeyError | TypeCastError
          raise Core::Errors::UnauthorizedError.new
        end
      end
    end
  end
end
