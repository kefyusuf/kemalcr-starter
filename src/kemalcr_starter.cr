require "kemal"
require "./core/config/settings"
require "./core/errors/api_error"
require "./core/errors/error_handler"
require "./core/http/request_context"
require "./core/http/request_context_handler"
require "./core/idempotency/service"
require "./core/logging/request_log_context"
require "./core/security/security_headers_handler"
require "./core/tenancy/authentication_handler"
require "./core/events/events"
require "./core/rbac/rbac"
require "./infrastructure/crypto/password_hasher"
require "./infrastructure/crypto/api_key_secret_hasher"
require "./infrastructure/crypto/token_fingerprint"
require "./infrastructure/db/connection_manager"
require "./infrastructure/db/migrator"
require "./infrastructure/db/repository"
require "./infrastructure/db/rbac_repository"
require "./infrastructure/db/api_key_repository"
require "./infrastructure/db/idempotency_key_repository"
require "./infrastructure/db/organization_membership_repository"
require "./infrastructure/db/organization_repository"
require "./infrastructure/db/user_repository"
require "./infrastructure/db/user_session_repository"
require "./infrastructure/db/outbox_event_repository"
require "./infrastructure/outbox/publisher_stats"
require "./infrastructure/outbox/redis_notifier"
require "./infrastructure/outbox/outbox_publisher"
require "./infrastructure/jwt/token_provider"
require "./infrastructure/redis/client_manager"
require "./modules/identity/events"
require "./modules/identity/auth_service"
require "./modules/identity/auth_throttle"
require "./modules/identity/me_service"
require "./modules/identity/me_routes"
require "./modules/identity/auth_routes"
require "./modules/api_keys/events"
require "./modules/api_keys/api_key_service"
require "./modules/api_keys/api_key_routes"
require "./modules/organizations/events"
require "./modules/organizations/organization_service"
require "./modules/organizations/organization_routes"
require "./infrastructure/db/processed_event_repository"

module KemalcrStarter
  VERSION = "0.1.0"

  add_context_storage_type(KemalcrStarter::Core::Http::RequestContext)

  class App
    @@settings : Core::Config::Settings?
    @@auth_service : Modules::Identity::AuthService?
    @@auth_throttle : Modules::Identity::AuthThrottle?
    @@api_key_service : Modules::ApiKeys::ApiKeyService?
    @@idempotency_service : Core::Idempotency::Service?
    @@me_service : Modules::Identity::MeService?
    @@organization_service : Modules::Organizations::OrganizationService?
    @@handler_registry : Core::Events::HandlerRegistry?
    @@outbox_publisher : Infrastructure::Outbox::OutboxPublisher?
    @@rbac_service : Core::Rbac::AuthorizationService?

    def self.settings : Core::Config::Settings
      @@settings ||= Core::Config::Settings.from_env(version: VERSION)
    end

    def self.auth_service : Modules::Identity::AuthService
      @@auth_service ||= Modules::Identity::AuthService.new(
        settings,
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
      )
    end

    def self.auth_throttle : Modules::Identity::AuthThrottle
      @@auth_throttle ||= Modules::Identity::RedisAuthThrottle.new(
        redis_url: settings.redis_url,
        login_limit: settings.auth_login_throttle_limit,
        refresh_limit: settings.auth_refresh_throttle_limit,
        window_seconds: settings.auth_throttle_window_seconds
      )
    end

    def self.install_auth_throttle(throttle : Modules::Identity::AuthThrottle) : Nil
      @@auth_throttle = throttle
    end

    def self.me_service : Modules::Identity::MeService
      @@me_service ||= Modules::Identity::MeService.new(
        Infrastructure::DB::ConnectionManager.client(settings.database_url)
      )
    end

    def self.idempotency_service : Core::Idempotency::Service
      @@idempotency_service ||= Core::Idempotency::Service.new(
        settings,
        Infrastructure::DB::ConnectionManager.client(settings.database_url)
      )
    end

    def self.api_key_service : Modules::ApiKeys::ApiKeyService
      @@api_key_service ||= Modules::ApiKeys::ApiKeyService.new(
        settings,
        Infrastructure::DB::ConnectionManager.client(settings.database_url)
      )
    end

    def self.organization_service : Modules::Organizations::OrganizationService
      @@organization_service ||= Modules::Organizations::OrganizationService.new(
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
      )
    end

    def self.handler_registry : Core::Events::HandlerRegistry
      @@handler_registry ||= Core::Events::HandlerRegistry.new
    end

    def self.rbac_service : Core::Rbac::AuthorizationService
      @@rbac_service ||= Core::Rbac::AuthorizationService.new(
        Infrastructure::DB::RbacRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
      )
    end

    def self.outbox_publisher : Infrastructure::Outbox::OutboxPublisher
      @@outbox_publisher ||= Infrastructure::Outbox::OutboxPublisher.new(
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        ),
        handler_registry,
        poll_interval: Time::Span.new(nanoseconds: settings.event_poll_interval_ms * 1_000_000),
        batch_size: settings.event_batch_size,
        max_retries: settings.event_max_retries,
        redis_url: settings.redis_url
      )
    end

    def self.current_correlation_id : String?
      Kemal.config.context_storage["request_context"]?.try do |ctx|
        ctx.as(Core::Http::RequestContext).request_id
      end
    end

    def self.reset_services : Nil
      @@auth_service = nil
      @@auth_throttle = nil
      @@api_key_service = nil
      @@idempotency_service = nil
      @@me_service = nil
      @@organization_service = nil
      @@handler_registry = nil
      @@outbox_publisher = nil
      @@rbac_service = nil
    end

    def self.configure : Nil
      Kemal.config.env = settings.environment
      Kemal.config.host_binding = settings.host
      Kemal.config.port = settings.port
      Kemal.config.powered_by_header = false
      Kemal.config.always_rescue = settings.always_rescue
      Kemal.config.add_handler(Core::Http::RequestContextHandler.new(settings))
      Kemal.config.add_handler(Core::Errors::ErrorHandler.new)
      Kemal.config.add_handler(Core::Tenancy::AuthenticationHandler.new(auth_service, api_key_service))
      Kemal.config.add_handler(Core::Security::SecurityHeadersHandler.new)
    end

    def self.request_context(env : HTTP::Server::Context) : Core::Http::RequestContext
      env.get("request_context").as(Core::Http::RequestContext)
    end

    def self.draw_routes : Nil
      get "/health" do |env|
        env.status(200).json(
          {
            status:      "ok",
            service:     settings.service_name,
            environment: settings.environment,
            request_id:  request_context(env).request_id,
          }
        )
      end

      get "/ready" do |env|
        postgres_status = Infrastructure::DB::ConnectionManager.ready?(settings.database_url) ? "up" : "down"
        redis_status = Infrastructure::Redis::ClientManager.ready?(settings.redis_url) ? "up" : "down"
        event_system = publisher_health
        ready = postgres_status == "up" && redis_status == "up" && event_system == "up"

        env.status(200).json(
          {
            status: ready ? "ready" : "degraded",
            checks: {
              postgres:     postgres_status,
              redis:        redis_status,
              event_system: event_system,
            },
            request_id: request_context(env).request_id,
          }
        )
      end

      get "/version" do |env|
        env.status(200).json(
          {
            service:    settings.service_name,
            version:    settings.version,
            build_time: settings.build_time,
            git_sha:    settings.git_sha,
            request_id: request_context(env).request_id,
          }
        )
      end

      get "/openapi" do |env|
        env.response.content_type = "application/yaml"
        env.response.headers["X-Request-Id"] = request_context(env).request_id
        File.read(settings.openapi_path)
      end

      get "/events/metrics" do |env|
        stats = outbox_publisher.stats
        env.status(200).json(
          {
            dispatched:  stats.dispatched,
            failed:      stats.failed,
            dead_letter: stats.dead_letter,
            last_poll:   stats.last_poll_at.try(&.to_rfc3339),
            service:     settings.service_name,
            request_id:  request_context(env).request_id,
          }
        )
      end

      get "/events/dead-letter" do |env|
        repo = Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
        items = repo.list_dead_letters.map do |dl|
          {
            id:             dl.id,
            original_event_id: dl.original_event_id,
            event_type:     dl.event_type,
            aggregate_type: dl.aggregate_type,
            aggregate_id:   dl.aggregate_id,
            failure_reason: dl.failure_reason,
            retry_count:    dl.retry_count,
            failed_at:      dl.failed_at.to_rfc3339,
          }
        end
        env.status(200).json({dead_letters: items, count: items.size, request_id: request_context(env).request_id})
      end

      post "/events/dead-letter/:id/requeue" do |env|
        repo = Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
        id = env.params.url["id"]
        if repo.requeue_dead_letter(id)
          env.status(200).json({status: "requeued", request_id: request_context(env).request_id})
        else
          env.status(404).json({status: "not_found", request_id: request_context(env).request_id})
        end
      end

      Modules::Identity::AuthRoutes.draw
      Modules::Identity::MeRoutes.draw
      Modules::ApiKeys::ApiKeyRoutes.draw
      Modules::Organizations::OrganizationRoutes.draw
    end

    def self.publisher_health : String
      return "disabled" unless @@outbox_publisher
      return "down" unless outbox_publisher.running?

      last_poll = outbox_publisher.stats.last_poll_at
      return "starting" unless last_poll

      poll_interval_ms = settings.event_poll_interval_ms
      threshold = Time.utc - Time::Span.new(nanoseconds: poll_interval_ms * 2 * 1_000_000)
      last_poll > threshold ? "up" : "degraded"
    end

    def self.boot : Nil
      configure
      draw_routes
      outbox_publisher.start
    end
  end
end
