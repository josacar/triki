require "../src/*"
require "spectator"

Spectator.configure do |config|
  config.fail_fast = true
end

Log.setup_from_env(default_level: :none)
