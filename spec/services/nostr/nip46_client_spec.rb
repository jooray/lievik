# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nostr::Nip46Client do
  let(:keypair) { Nostr::Keygen.new.generate_key_pair }
  let(:auth_session) do
    NostrAuthSession.new(
      session_id: SecureRandom.uuid,
      temp_pubkey: keypair.public_key.to_s,
      temp_privkey: keypair.private_key.to_s,
      secret: "secret",
      relay_url: '["wss://relay.example"]',
      expires_at: 5.minutes.from_now,
      created_at: Time.current
    )
  end
  subject(:client) { described_class.new(auth_session) }

  it "only accepts a response-shaped connect result containing the secret" do
    expect(client.valid_connect_response?({ "id" => "request", "result" => "secret" })).to be(true)
    expect(client.valid_connect_response?({ "id" => "request", "result" => "ack" })).to be(false)
    expect(client.valid_connect_response?({ "id" => "request", "method" => "connect", "params" => ["secret"] })).to be(false)
    expect(client.valid_connect_response?({ "method" => "connect", "params" => ["secret"] })).to be(false)
  end

  it "builds an NIP-44 encrypted get_public_key request" do
    signer = Nostr::Keygen.new.generate_key_pair
    request = client.build_request_event(signer.public_key.to_s, "get_public_key")
    conv_key = Nostr::Nip44.conversation_key(signer.private_key.to_s, keypair.public_key.to_s)
    payload = JSON.parse(Nostr::Nip44.decrypt(conv_key, request[:event]["content"]))

    expect(payload).to include("id" => request[:request_id], "method" => "get_public_key", "params" => [])
  end

  it "returns nil for malformed NIP-04 ciphertext and IV" do
    signer = Nostr::Keygen.new.generate_key_pair.public_key.to_s

    expect(client.decrypt_nip04("not-base64!?iv=also-bad!", signer)).to be_nil
    expect(client.decrypt_nip04("#{Base64.strict_encode64("short")}?iv=#{Base64.strict_encode64("short")}", signer)).to be_nil
  end
end
