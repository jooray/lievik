# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nostr::Nip44 do
  let(:conversation_key) { ["c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d"].pack("H*") }

  it "decrypts an official NIP-44 v2 vector" do
    payload = "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb"

    expect(described_class.decrypt(conversation_key, payload)).to eq("a")
  end

  it "encrypts a payload that round trips with canonical padding" do
    nonce = "n" * 32
    encrypted = described_class.encrypt(conversation_key, "get_public_key", nonce: nonce)

    expect(described_class.decrypt(conversation_key, encrypted)).to eq("get_public_key")
  end

  it "rejects malformed base64" do
    expect { described_class.decrypt(conversation_key, "not base64!") }.to raise_error(Nostr::Nip44::DecryptionError)
  end
end
