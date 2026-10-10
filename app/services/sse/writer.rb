# frozen_string_literal: true

module Sse
  # Writes server-sent events to an ActionController::Live stream. Every data
  # payload is JSON (a chunk is a JSON string), which is what the web's
  # Stimulus controllers and the app both parse.
  class Writer
    def initialize(stream)
      @stream = stream
    end

    def event(name, data)
      @stream.write "event: #{name}\ndata: #{data.to_json}\n\n"
    end

    def error(message)
      event("error", { message: message })
    end
  end
end
