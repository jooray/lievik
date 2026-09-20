# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nostr::KeyConverter, "bunker:// parsing" do
  let(:pubkey) { "a" * 64 }

  describe ".bunker_uri?" do
    it "recognises a well-formed URI" do
      expect(described_class.bunker_uri?("bunker://#{pubkey}?relay=wss://nos.lol")).to be(true)
    end

    # iOS capitalises the first typed character. Routing on a case-sensitive
    # match sent these down the "paste a key" branch, where they died with an
    # unrelated bech32 error instead of a bunker-specific message.
    it "recognises a capitalised scheme" do
      expect(described_class.bunker_uri?("Bunker://#{pubkey}?relay=wss://nos.lol")).to be(true)
    end

    it "tolerates surrounding whitespace from a paste" do
      expect(described_class.bunker_uri?("  bunker://#{pubkey}?relay=wss://nos.lol\n")).to be(true)
    end

    # Routing is deliberately looser than validity: a malformed bunker string is
    # still a bunker string, and must report a bunker error.
    it "routes a malformed bunker string to the bunker branch" do
      expect(described_class.bunker_uri?("bunker://nonsense")).to be(true)
      expect(described_class.parse_bunker_uri("bunker://nonsense")).to be_nil
    end

    it "does not claim an nsec or npub" do
      expect(described_class.bunker_uri?("npub1abc")).to be(false)
      expect(described_class.bunker_uri?("nostrconnect://#{pubkey}?relay=wss://nos.lol")).to be(false)
    end
  end

  describe ".parse_bunker_uri" do
    it "extracts pubkey, relays and secret" do
      uri = "bunker://#{pubkey}?relay=wss%3A%2F%2Fnos.lol&relay=wss%3A%2F%2Frelay.primal.net&secret=s3cr3t"

      expect(described_class.parse_bunker_uri(uri)).to eq(
        pubkey: pubkey,
        relays: ["wss://nos.lol", "wss://relay.primal.net"],
        secret: "s3cr3t"
      )
    end

    it "accepts unescaped relay values, which signers do emit" do
      result = described_class.parse_bunker_uri("bunker://#{pubkey}?relay=wss://nos.lol")

      expect(result[:relays]).to eq(["wss://nos.lol"])
    end

    it "treats a missing secret as nil rather than empty string" do
      expect(described_class.parse_bunker_uri("bunker://#{pubkey}?relay=wss://nos.lol")[:secret]).to be_nil
    end

    it "lowercases an uppercased hex pubkey" do
      result = described_class.parse_bunker_uri("bunker://#{("A" * 64)}?relay=wss://nos.lol")

      expect(result[:pubkey]).to eq("a" * 64)
    end

    # Without a relay there is nowhere to send the connect request; a signer
    # pubkey on its own is not reachable.
    it "rejects a URI with no relay" do
      expect(described_class.parse_bunker_uri("bunker://#{pubkey}")).to be_nil
      expect(described_class.parse_bunker_uri("bunker://#{pubkey}?secret=x")).to be_nil
    end

    it "rejects a pubkey that is not 64 hex characters" do
      expect(described_class.parse_bunker_uri("bunker://abc?relay=wss://nos.lol")).to be_nil
      expect(described_class.parse_bunker_uri("bunker://#{'z' * 64}?relay=wss://nos.lol")).to be_nil
    end

    it "returns nil rather than raising on junk" do
      ["", "bunker://", "not a uri", "bunker://%%%?relay=x"].each do |junk|
        expect { described_class.parse_bunker_uri(junk) }.not_to raise_error
        expect(described_class.parse_bunker_uri(junk)).to be_nil
      end
    end
  end
end
