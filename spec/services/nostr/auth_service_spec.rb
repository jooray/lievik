# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nostr::AuthService do
  let(:keypair) { Nostr::Keygen.new.generate_key_pair }
  let(:challenge) { SecureRandom.hex(32) }

  def signed_proof(proof_challenge = challenge, domain: nil)
    tags = [["challenge", proof_challenge]]
    tags << ["domain", domain] if domain
    event = Nostr::Event.new(
      pubkey: keypair.public_key.to_s,
      created_at: Time.current.to_i,
      kind: 22242,
      tags: tags,
      content: "Sign in to Lievik"
    )
    event.sign(keypair.private_key).to_h.to_json
  end

  it "returns the signing pubkey for a valid server challenge" do
    expect(described_class.new.verify_nip07_auth(signed_proof, challenge)).to eq(keypair.public_key.to_s)
  end

  it "rejects a proof for another challenge" do
    expect(described_class.new.verify_nip07_auth(signed_proof("other"), challenge)).to be(false)
  end

  it "rejects a modified proof" do
    proof = JSON.parse(signed_proof)
    proof["content"] = "modified"

    expect(described_class.new.verify_nip07_auth(proof.to_json, challenge)).to be(false)
  end

  describe "domain binding" do
    it "accepts a proof signed for the expected host" do
      proof = signed_proof(domain: "lievik.cypherpunk.today")

      expect(described_class.new.verify_nip07_auth(proof, challenge, domain: "lievik.cypherpunk.today"))
        .to eq(keypair.public_key.to_s)
    end

    it "rejects a proof signed for a different host" do
      proof = signed_proof(domain: "evil.example")

      expect(described_class.new.verify_nip07_auth(proof, challenge, domain: "lievik.cypherpunk.today"))
        .to be(false)
    end

    it "matches the host case-insensitively" do
      proof = signed_proof(domain: "Lievik.Cypherpunk.Today")

      expect(described_class.new.verify_nip07_auth(proof, challenge, domain: "lievik.cypherpunk.today"))
        .to eq(keypair.public_key.to_s)
    end

    # Deliberate: the domain tag ships with the JS that produces it, so a
    # browser still running the previous bundle must not be locked out.
    it "accepts a proof with no domain tag from an older client" do
      expect(described_class.new.verify_nip07_auth(signed_proof, challenge, domain: "lievik.cypherpunk.today"))
        .to eq(keypair.public_key.to_s)
    end
  end

  it "rejects malformed tags without raising" do
    proof = JSON.parse(signed_proof)
    proof["tags"] = "not-an-array"

    expect { described_class.new.verify_nip07_auth(proof.to_json, challenge) }.not_to raise_error
    expect(described_class.new.verify_nip07_auth(proof.to_json, challenge)).to be(false)
  end
end
