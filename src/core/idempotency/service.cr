require "digest/sha256"
require "json"
require "uuid"

module KemalcrStarter
  module Core
    module Idempotency
      record Response,
        status_code : Int32,
        body : String

      class Service
        LOCK_TTL = 30.seconds

        def initialize(@settings : Core::Config::Settings, @database : ::DB::Database)
          @repository = Infrastructure::DB::IdempotencyKeyRepository.new(@database)
          @redis = Infrastructure::Redis::ClientManager.client(@settings.redis_url)
        end

        def execute(idempotency_key : String?, method : String, route_scope : String, actor_id : String, request_body : String, &block : -> Response) : Response
          key = idempotency_key.to_s.strip
          return yield if key.empty?

          fingerprint = request_fingerprint(method, route_scope, actor_id, request_body)
          scope = request_scope(method, route_scope, actor_id)
          lock_key = lock_key_for(scope, key)

          if existing = @repository.find(scope, key)
            return resolve_existing(existing, fingerprint)
          end

          raise Core::Errors::ConflictError.new("Another request with the same idempotency key is already in progress.") unless acquire_lock(lock_key, fingerprint)

          if existing = @repository.find(scope, key)
            return resolve_existing(existing, fingerprint)
          end

          record = @repository.create(generate_id("idem"), scope, key, fingerprint, Time.utc + LOCK_TTL)

          begin
            response = yield
            @repository.complete(record.id, response.status_code, response.body)
            response
          rescue ex
            @repository.delete(record.id)
            raise ex
          ensure
            release_lock(lock_key)
          end
        end

        private def acquire_lock(lock_key : String, fingerprint : String) : Bool
          @redis.set(lock_key, fingerprint, ex: LOCK_TTL, nx: true) == "OK"
        rescue
          raise Core::Errors::ConflictError.new("Idempotency is temporarily unavailable.")
        end

        private def release_lock(lock_key : String) : Nil
          @redis.del(lock_key)
        rescue
        end

        private def resolve_existing(record : Infrastructure::DB::IdempotencyKeyRecord, fingerprint : String) : Response
          raise Core::Errors::ConflictError.new("The idempotency key was already used with a different request payload.") if record.request_fingerprint != fingerprint

          if status_code = record.response_status
            if body = record.response_body_ref
              return Response.new(status_code: status_code, body: body)
            end
          end

          raise Core::Errors::ConflictError.new("Another request with the same idempotency key is already in progress.")
        end

        private def request_scope(method : String, route_scope : String, actor_id : String) : String
          "#{actor_id}:#{method.upcase}:#{route_scope}"
        end

        private def request_fingerprint(method : String, route_scope : String, actor_id : String, request_body : String) : String
          normalized_body = normalize_body(request_body)
          Digest::SHA256.hexdigest([method.upcase, route_scope, actor_id, normalized_body].join(":"))
        end

        private def normalize_body(request_body : String) : String
          return "" if request_body.blank?

          JSON.parse(request_body).to_json
        rescue JSON::ParseException
          request_body.strip
        end

        private def lock_key_for(scope : String, idempotency_key : String) : String
          Infrastructure::Redis::ClientManager.namespaced_key(
            "idempotency",
            "lock",
            Digest::SHA256.hexdigest("#{scope}:#{idempotency_key}")
          )
        end

        private def generate_id(prefix : String) : String
          "#{prefix}_#{UUID.random}"
        end
      end
    end
  end
end
