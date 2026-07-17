# frozen_string_literal: true

require "rails_helper"

# The WebSocket frame reader is the shared NIP-46 engine component (identical in
# lievik and nostr-emanator). It reads one server->client frame off a socket
# using non-blocking reads bounded by a deadline.
RSpec.describe Nostr::WebsocketFrameReader do
  # Minimal socket stand-in that hands out queued byte chunks via read_nonblock.
  # Chunks are sized so a full frame is always available without ever needing
  # IO.select (which a real IO would service).
  class FakeSocket
    def initialize(chunks)
      @chunks = chunks.dup
    end

    def read_nonblock(maxlen, exception:)
      raise ArgumentError, "expected exception: false" unless exception == false
      return :wait_readable if @chunks.empty?

      item = @chunks.shift
      return item if item == :wait_readable
      return item if item.bytesize <= maxlen

      @chunks.unshift(item.byteslice(maxlen..))
      item.byteslice(0, maxlen)
    end
  end

  it "assembles a text frame from partial socket reads" do
    socket = FakeSocket.new([ "\x81", "\x02", "o", "k" ])

    expect(described_class.read(socket, deadline: 1.second.from_now)).to eq("ok")
  end

  it "rejects a frame larger than the configured maximum before reading its payload" do
    socket = FakeSocket.new([ "\x81\x7f", [ 6 ].pack("Q>") ])

    expect { described_class.read(socket, deadline: 1.second.from_now, max_size: 5) }
      .to raise_error(described_class::FrameError, /exceeds/)
  end

  it "raises when the read deadline has already passed" do
    socket = FakeSocket.new([ "\x81\x02ok" ])

    expect { described_class.read(socket, deadline: 1.second.ago) }
      .to raise_error(described_class::FrameError, /deadline/)
  end
end
