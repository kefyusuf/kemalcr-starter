ENV["KEMAL_ENV"] = "test"

require "spec"
require "spec-kemal"
require "../src/app"

Spec.before_each do
  Kemal.config.clear
  Kemal.config.env = "test"
  KemalcrStarter::App.reset_services
  KemalcrStarter::App.configure
  Kemal.config.setup
end

Spec.after_each do
  KemalcrStarter::App.reset_services
  Kemal.config.clear
end
