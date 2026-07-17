# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nostr::Nip46Listener::Handshake do
  it "creates one logical request shared by all relays" do
    client = instance_double(Nostr::Nip46Client)
    request = { request_id: "one", event: { "id" => "event" } }
    allow(client).to receive(:build_request_event).once.and_return(request)
    state = described_class.new
    state.set_signer("a" * 64)

    expect(state.request(client)).to equal(request)
    expect(state.request(client)).to equal(request)
    expect(state.known_request?("one")).to be(true)
  end
end

RSpec.describe Nostr::Nip46Listener do
  it "ignores valid JSON with an unexpected relay message shape" do
    listener = described_class.allocate
    client = instance_double(Nostr::Nip46Client)
    allow(client).to receive(:read_websocket_frame).and_return('{"EVENT":"bad"}')
    listener.instance_variable_set(:@client, client)
    socket = instance_double(IO)
    allow(IO).to receive(:select).and_return([[socket]])

    result = listener.send(:read_signer_event, socket, 1.second.from_now)

    expect(result).to eq(:idle)
  end

  it "ignores malformed EVENT payloads without calling protocol decryption" do
    listener = described_class.allocate
    client = instance_double(Nostr::Nip46Client)
    allow(client).to receive(:read_websocket_frame).and_return('["EVENT","sub","bad"]')
    listener.instance_variable_set(:@client, client)
    socket = instance_double(IO)
    allow(IO).to receive(:select).and_return([[socket]])

    result = listener.send(:read_signer_event, socket, 1.second.from_now)

    expect(result).to eq(:idle)
  end
end
