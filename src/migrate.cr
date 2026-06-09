require "./kemalcr_starter"

action = ARGV[0]? || "up"

settings = KemalcrStarter::Core::Config::Settings.from_env(version: KemalcrStarter::VERSION)
KemalcrStarter::Infrastructure::DB::Migrator.new(settings).run(action)
