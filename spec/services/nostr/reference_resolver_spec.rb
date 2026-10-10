# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nostr::ReferenceResolver do
  let(:user) { User.create!(npub: "npub1me", pubkey_hex: "9" * 64) }
  let(:alice) { Nostr::KeyConverter.hex_to_npub("a" * 64) }
  let!(:source) { user.sources.create!(source_type: :nostr, identifier: alice, name: "Alice") }
  let(:resolver) { described_class.new(user) }

  before { allow(WarmNostrReferenceCacheJob).to receive(:perform_later) }

  it "resolves a profile from the local sources" do
    expect(resolver.resolve(alice)).to include(type: :profile, npub: alice, display_name: "Alice",
                                               url: "https://yakihonne.com/profile/#{alice}")
  end

  it "resolves a locally stored note with its author, truncated for a preview" do
    source.events.create!(external_id: "b" * 64, content: "x" * 400, published_at: 1.day.ago)
    note = Nostr::KeyConverter.hex_to_note("b" * 64)

    ref = resolver.resolve(note)
    expect(ref).to include(type: :event, resolved: true, author_name: "Alice", url: "https://yakihonne.com/note/#{note}")
    expect(ref[:content].length).to eq(300)
  end

  it "schedules a relay fetch for an unknown note and reports it unresolved" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    note = Nostr::KeyConverter.hex_to_note("c" * 64)

    expect(resolver.resolve(note)).to include(type: :event, resolved: false)
    expect(WarmNostrReferenceCacheJob).to have_received(:perform_later).with("event", "c" * 64, [])
  ensure
    Rails.cache = previous_cache if previous_cache
  end

  it "returns nil for an identifier that does not decode, and memoizes" do
    expect(resolver.resolve("npub1notreally")).to be_nil
    expect(::Source).to receive(:find_by).once.and_call_original
    2.times { resolver.resolve(Nostr::KeyConverter.hex_to_npub("e" * 64)) }
  end

  it "lists the identifiers in content once each" do
    content = "nostr:#{alice} and again nostr:#{alice}"
    expect(described_class.identifiers_in(content)).to eq([ alice ])
  end
end
