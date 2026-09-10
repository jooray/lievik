# frozen_string_literal: true

require "rails_helper"

# The event detail page must offer a way *out* of Lievik and back to the note:
# a link into whichever Nostr client the user configured, and the bech32 id for
# pasting elsewhere. Both are derived from the user's link templates, so a
# changed template has to change the rendered link.
RSpec.describe "Event detail Nostr links", type: :request do
  let(:event_hex) { "a1" * 32 }
  let(:author_hex) { "b2" * 32 }

  let!(:user) { User.create!(npub: "npub1owner", pubkey_hex: "1" * 64, display_name: "owner") }
  let!(:nostr_source) do
    user.sources.create!(source_type: :nostr, identifier: Nostr::KeyConverter.hex_to_npub(author_hex),
      name: "Source A", distance: 3)
  end
  let!(:rss_source) do
    user.sources.create!(source_type: :rss, identifier: "https://example.com/feed.xml", name: "Feed", distance: 5)
  end

  let!(:nostr_event) do
    nostr_source.events.create!(external_id: event_hex, content: "A note", event_type: :original,
      published_at: 1.day.ago, raw_data: { "pubkey" => author_hex, "kind" => 1 })
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  it "links a Nostr event to the default client and offers the nevent to copy" do
    get event_path(nostr_event)

    nevent = nostr_event.nevent_id
    expect(nevent).to start_with("nevent1")
    expect(response.body).to include("https://yakihonne.com/note/#{nevent}")
    expect(response.body).to include("Open in yakihonne.com")
    expect(response.body).to include(%(data-clipboard-text-value="#{nevent}"))
    expect(response.body).to include("Copy nevent")
  end

  it "uses the user's configured client template" do
    user.update!(event_link_template: "https://primal.net/e/{eventid}")

    get event_path(nostr_event)

    expect(response.body).to include("https://primal.net/e/#{nostr_event.nevent_id}")
    expect(response.body).to include("Open in primal.net")
    expect(response.body).not_to include("yakihonne.com/note")
  end

  it "offers no Nostr id for a non-Nostr event" do
    rss_event = rss_source.events.create!(external_id: "rss-1", content: "From a feed", event_type: :original,
      published_at: 1.day.ago, metadata: { "link" => "https://example.com/post" })

    get event_path(rss_event)

    expect(response.body).to include("https://example.com/post")
    expect(response.body).not_to include("Copy nevent")
    expect(response.body).not_to include("data-clipboard-text-value")
  end
end
