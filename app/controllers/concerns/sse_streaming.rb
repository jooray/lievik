# frozen_string_literal: true

# Server-sent event responses for ActionController::Live controllers (web and
# app API share the stream services under app/services/streams and
# ChannelContents::Generation; this is only the transport).
module SseStreaming
  extend ActiveSupport::Concern

  private

  # Sets the SSE headers, yields an Sse::Writer and always closes the stream.
  def stream_sse
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no" # Disable nginx buffering
    yield Sse::Writer.new(response.stream)
  ensure
    response.stream.close
  end
end
