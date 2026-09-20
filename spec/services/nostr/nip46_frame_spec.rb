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

  # Regression: the length ladder used two sequential `if`s instead of
  # `if`/`elsif`. A 127-byte payload is too long for the 7-bit form, so it is
  # encoded with the 126 (16-bit) form — whose extended length is the literal
  # 127. The second `if` then fired and consumed 8 payload bytes as a bogus
  # 64-bit length, desyncing the socket for the rest of the connection. Relay
  # control messages (EOSE, OK, NOTICE, CLOSED) land on 127 bytes easily, so
  # this killed logins intermittently and unreproducibly.
  it "reads a 127-byte payload without mistaking it for a 64-bit length" do
    payload = "x" * 127
    socket = FakeSocket.new([ "\x81\x7e", [ 127 ].pack("n"), payload ])

    expect(described_class.read(socket, deadline: 1.second.from_now)).to eq(payload)
  end

  it "still reads a genuine 64-bit length frame" do
    payload = "y" * 70_000
    socket = FakeSocket.new([ "\x81\x7f", [ payload.bytesize ].pack("Q>"), payload ])

    expect(described_class.read(socket, deadline: 5.seconds.from_now)).to eq(payload)
  end

  it "raises when the read deadline has already passed" do
    socket = FakeSocket.new([ "\x81\x02ok" ])

    expect { described_class.read(socket, deadline: 1.second.ago) }
      .to raise_error(described_class::FrameError, /deadline/)
  end
end
