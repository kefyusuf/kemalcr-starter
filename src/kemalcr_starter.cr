require "kemal"
require "./core/config/settings"
require "./core/errors/api_error"
require "./core/errors/error_handler"
require "./core/http/request_context"
require "./core/http/request_context_handler"
require "./core/http/pagination"
require "./core/idempotency/service"
require "./core/logging/request_log_context"
require "./core/logging/access_log_handler"
require "./core/security/security_headers_handler"
require "./core/security/cors_handler"
require "./core/tenancy/authentication_handler"
require "./infrastructure/http/webhook_destination"
require "./core/events/events"
require "./core/modules/module_registry"
require "./core/events/handlers/organization_audit_handler"
require "./core/events/handlers/membership_audit_handler"
require "./core/events/handlers/api_key_audit_handler"
require "./core/events/handlers/user_audit_handler"
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
require "./infrastructure/db/audit_log_repository"
require "./infrastructure/outbox/publisher_stats"
require "./infrastructure/outbox/redis_notifier"
require "./infrastructure/outbox/outbox_publisher"
require "./infrastructure/jwt/token_provider"
require "./infrastructure/redis/client_manager"
require "./infrastructure/email/email_adapter"
require "./infrastructure/email/console_email_adapter"
require "./infrastructure/email/smtp_email_adapter"
require "./infrastructure/db/password_reset_token_repository"
require "./modules/identity/events"
require "./modules/identity/auth_service"
require "./modules/identity/auth_throttle"
require "./modules/identity/me_service"
require "./modules/identity/me_routes"
require "./modules/identity/auth_routes"
require "./modules/identity/password_reset_service"
require "./modules/identity/password_reset_routes"
require "./infrastructure/db/webhook_repository"
require "./modules/webhooks/webhook_service"
require "./modules/webhooks/delivery_handler"
require "./modules/webhooks/webhook_routes"
require "./infrastructure/db/product_repository"
require "./modules/products/events"
require "./modules/products/product_service"
require "./modules/products/product_routes"
require "./infrastructure/billing/billing_adapter"
require "./infrastructure/billing/null_billing_adapter"
require "./infrastructure/billing/stripe_billing_adapter"
require "./infrastructure/billing/stripe_webhook_verifier"
require "./modules/billing/events"
require "./modules/billing/billing_service"
require "./modules/billing/billing_routes"
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
    @@audit_log_repository : Infrastructure::DB::AuditLogRepository?
    @@email_adapter : Infrastructure::Email::EmailAdapter?
    @@password_reset_service : Modules::Identity::PasswordResetService?
    @@webhook_service : Modules::Webhooks::WebhookService?
    @@product_service : Modules::Products::ProductService?
    @@billing_adapter : Infrastructure::Billing::BillingAdapter?
    @@billing_service : Modules::Billing::BillingService?

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
        register_limit: settings.auth_register_throttle_limit,
        window_seconds: settings.auth_throttle_window_seconds
      )
    end

    def self.install_auth_throttle(throttle : Modules::Identity::AuthThrottle) : Nil
      @@auth_throttle = throttle
    end

    def self.email_adapter : Infrastructure::Email::EmailAdapter
      @@email_adapter ||= build_email_adapter
    end

    def self.install_email_adapter(adapter : Infrastructure::Email::EmailAdapter) : Nil
      @@email_adapter = adapter
    end

    def self.password_reset_service : Modules::Identity::PasswordResetService
      @@password_reset_service ||= Modules::Identity::PasswordResetService.new(
        settings,
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        email_adapter,
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
      )
    end

    def self.webhook_service : Modules::Webhooks::WebhookService
      @@webhook_service ||= Modules::Webhooks::WebhookService.new(
        settings,
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
      )
    end

    def self.product_service : Modules::Products::ProductService
      @@product_service ||= Modules::Products::ProductService.new(
        settings,
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
      )
    end

    def self.billing_adapter : Infrastructure::Billing::BillingAdapter
      @@billing_adapter ||= build_billing_adapter
    end

    def self.install_billing_adapter(adapter : Infrastructure::Billing::BillingAdapter) : Nil
      @@billing_adapter = adapter
    end

    def self.billing_service : Modules::Billing::BillingService
      @@billing_service ||= Modules::Billing::BillingService.new(
        settings,
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        billing_adapter,
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
      )
    end

    private def self.build_billing_adapter : Infrastructure::Billing::BillingAdapter
      case settings.billing_adapter
      when "stripe"
        key = settings.stripe_api_key
        raise ArgumentError.new("STRIPE_API_KEY is required when BILLING_ADAPTER=stripe") unless key
        Infrastructure::Billing::StripeBillingAdapter.new(key)
      else
        Infrastructure::Billing::NullBillingAdapter.new
      end
    end

    private def self.build_email_adapter : Infrastructure::Email::EmailAdapter
      case settings.email_adapter
      when "smtp"
        Infrastructure::Email::SmtpEmailAdapter.new(
          settings.smtp_host,
          settings.smtp_port,
          settings.smtp_username,
          settings.smtp_password,
          settings.email_from
        )
      else
        Infrastructure::Email::ConsoleEmailAdapter.new
      end
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
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        nil,
        rbac_service
      )
    end

    def self.organization_service : Modules::Organizations::OrganizationService
      @@organization_service ||= Modules::Organizations::OrganizationService.new(
        Infrastructure::DB::ConnectionManager.client(settings.database_url),
        Infrastructure::DB::OutboxEventRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        ),
        rbac_service
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

    def self.audit_log_repository : Infrastructure::DB::AuditLogRepository
      @@audit_log_repository ||= Infrastructure::DB::AuditLogRepository.new(
        Infrastructure::DB::ConnectionManager.client(settings.database_url)
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

    def self.register_event_handlers : Nil
      repo = audit_log_repository
      handler_registry.register("organization.created", Core::Events::OrganizationAuditHandler.new(repo))
      handler_registry.register("organization.updated", Core::Events::OrganizationAuditHandler.new(repo))
      handler_registry.register("organization.membership.invited", Core::Events::MembershipAuditHandler.new(repo))
      handler_registry.register("organization.membership.accepted", Core::Events::MembershipAuditHandler.new(repo))
      handler_registry.register("organization.membership.revoked", Core::Events::MembershipAuditHandler.new(repo))
      handler_registry.register("api_key.created", Core::Events::ApiKeyAuditHandler.new(repo))
      handler_registry.register("api_key.revoked", Core::Events::ApiKeyAuditHandler.new(repo))
      handler_registry.register("identity.user.created", Core::Events::UserAuditHandler.new(repo))
      handler_registry.register("identity.user.logged_in", Core::Events::UserAuditHandler.new(repo))
      handler_registry.register("identity.user.logged_out", Core::Events::UserAuditHandler.new(repo))
      handler_registry.register("identity.session.revoked", Core::Events::UserAuditHandler.new(repo))
      handler_registry.register("identity.user.password_reset", Core::Events::UserAuditHandler.new(repo))

      if Core::Plugins::ModuleRegistry.enabled?(settings, "webhooks")
        handler_registry.register("*", Modules::Webhooks::DeliveryHandler.new(webhook_service))
      end
    end

    def self.reset_services : Nil
      @@settings = nil
      @@auth_service = nil
      @@auth_throttle = nil
      @@api_key_service = nil
      @@idempotency_service = nil
      @@me_service = nil
      @@organization_service = nil
      @@handler_registry = nil
      @@outbox_publisher = nil
      @@rbac_service = nil
      @@audit_log_repository = nil
      @@email_adapter = nil
      @@password_reset_service = nil
      @@webhook_service = nil
      @@product_service = nil
      @@billing_adapter = nil
      @@billing_service = nil
    end

    def self.configure : Nil
      Kemal.config.env = settings.environment
      Kemal.config.host_binding = settings.host
      Kemal.config.port = settings.port
      Kemal.config.powered_by_header = false
      Kemal.config.always_rescue = settings.always_rescue
      Kemal.config.add_handler(Core::Security::CorsHandler.new)
      Kemal.config.add_handler(Core::Http::RequestContextHandler.new(settings))
      Kemal.config.add_handler(Core::Logging::AccessLogHandler.new)
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
            id:                dl.id,
            original_event_id: dl.original_event_id,
            event_type:        dl.event_type,
            aggregate_type:    dl.aggregate_type,
            aggregate_id:      dl.aggregate_id,
            failure_reason:    dl.failure_reason,
            retry_count:       dl.retry_count,
            failed_at:         dl.failed_at.to_rfc3339,
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

      get "/rbac/permissions" do |env|
        actor_id = request_context(env).actor_id
        raise Core::Errors::UnauthorizedError.new unless actor_id

        perms = Core::Rbac::Permission.values.map do |p|
          {name: p.to_s, roles: rbac_service.roles_for_permission(p)}
        end
        env.status(200).json({permissions: perms, request_id: request_context(env).request_id})
      end

      get "/rbac/roles" do |env|
        actor_id = request_context(env).actor_id
        raise Core::Errors::UnauthorizedError.new unless actor_id

        repo = Infrastructure::DB::RbacRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
        roles = {"owner"  => repo.list_permissions_for_role("owner"),
                 "admin"  => repo.list_permissions_for_role("admin"),
                 "member" => repo.list_permissions_for_role("member")}
        env.status(200).json({roles: roles, request_id: request_context(env).request_id})
      end

      post "/rbac/roles/seed" do |env|
        actor_id = request_context(env).actor_id
        raise Core::Errors::UnauthorizedError.new unless actor_id

        rbac_service.seed_default_roles!
        env.status(200).json({status: "seeded", request_id: request_context(env).request_id})
      end

      delete "/rbac/roles/:role/permissions/:permission" do |env|
        actor_id = request_context(env).actor_id
        raise Core::Errors::UnauthorizedError.new unless actor_id

        role_name = env.params.url["role"]
        perm_name = env.params.url["permission"]
        begin
          permission = Core::Rbac::Permission.from_s(perm_name)
        rescue ArgumentError
          env.status(422).json({status: "invalid_permission", request_id: request_context(env).request_id})
          next
        end

        repo = Infrastructure::DB::RbacRepository.new(
          Infrastructure::DB::ConnectionManager.client(settings.database_url)
        )
        repo.remove_permission(role_name, permission)
        env.status(200).json({status: "removed", request_id: request_context(env).request_id})
      end

      Modules::Identity::AuthRoutes.draw
      Modules::Identity::MeRoutes.draw
      Modules::ApiKeys::ApiKeyRoutes.draw
      Modules::Organizations::OrganizationRoutes.draw

      if Core::Plugins::ModuleRegistry.enabled?(settings, "password_reset")
        Modules::Identity::PasswordResetRoutes.draw
      end

      if Core::Plugins::ModuleRegistry.enabled?(settings, "webhooks")
        Modules::Webhooks::WebhookRoutes.draw
      end

      if Core::Plugins::ModuleRegistry.enabled?(settings, "products")
        Modules::Products::ProductRoutes.draw
      end

      if Core::Plugins::ModuleRegistry.enabled?(settings, "billing")
        Modules::Billing::BillingRoutes.draw
      end
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
      register_event_handlers
      draw_routes
      outbox_publisher.start
    end
  end
end
