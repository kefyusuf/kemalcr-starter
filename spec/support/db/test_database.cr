require "../../../src/kemalcr_starter"

module TestDatabase
  extend self

  def settings : KemalcrStarter::Core::Config::Settings
    KemalcrStarter::Core::Config::Settings.from_env(version: KemalcrStarter::VERSION)
  end

  def database : ::DB::Database
    KemalcrStarter::Infrastructure::DB::ConnectionManager.client(settings.database_url)
  end

  def migrate! : Nil
    KemalcrStarter::Infrastructure::DB::Migrator.new(settings).up
  end

  def truncate_all! : Nil
    database.exec "TRUNCATE TABLE audit_logs, idempotency_keys, api_keys, organization_memberships, organizations, user_sessions, users, outbox_events, dead_letter_events, rbac_role_permissions RESTART IDENTITY CASCADE"
  end
end
