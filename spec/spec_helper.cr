require "../src/*"
require "spectator"

Spectator.configure do |config|
  config.fail_fast = true
end

module Helpers::Log
  def self.io
    @@io ||= IO::Memory.new
  end
end


Triki.log = begin
                    io = Helpers::Log.io
                    backend = ::Log::IOBackend.new(io)
                    ::Log.builder.bind("*", :warning, backend)
                    ::Log.for("triki")
                  end
