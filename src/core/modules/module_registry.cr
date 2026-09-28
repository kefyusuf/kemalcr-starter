module KemalcrStarter
  module Core
    module Plugins
      # Plug-and-play module catalog. A module is on when its name is listed
      # in Settings.enabled_modules. Core modules cannot be disabled.
      module ModuleRegistry
        extend self

        CORE_MODULES = {"identity", "organizations", "api_keys", "system"}

        def enabled?(settings : Config::Settings, name : String) : Bool
          return true if CORE_MODULES.includes?(name)
          settings.enabled_modules.includes?(name)
        end

        def enabled_or_all(settings : Config::Settings) : Array(String)
          (CORE_MODULES.to_a + settings.enabled_modules).uniq
        end

        def known_pluggable : Array(String)
          {"password_reset", "webhooks"}.to_a
        end
      end
    end
  end
end
