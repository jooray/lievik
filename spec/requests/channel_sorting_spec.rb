# frozen_string_literal: true

require "rails_helper"

# The channel page can be ordered by AI rating (the default) or by the event's
# publication date. The recency orders are the interesting ones: they sort on a
# joined table, and they must keep honouring the channel's relevance threshold
# and the "Show used" toggle rather than quietly showing everything.
RSpec.describe "Channel event sorting", type: :request do
  let!(:user) { User.create!(npub: "npub1owner", pubkey_hex: "1" * 64, display_name: "owner") }
  let!(:source) { user.sources.create!(source_type: :manual, identifier: "src", name: "src", distance: 5) }

  let!(:channel) do
    user.channels.create!(
      name: "Newsletter", language: "en", prompt: "anything",
      settings: { "relevance_threshold" => 50 }
    )
  end

  # Rating order and recency order disagree on purpose: the oldest note is the
  # highest rated, so a test that passes under both orders proves nothing.
  let!(:old_high) { create_event("old-high", "Oldest note, best rated", 10.days.ago) }
  let!(:mid) { create_event("mid", "Middle note", 5.days.ago) }
  let!(:new_low) { create_event("new-low", "Newest note, worst rated", 1.day.ago) }

  let!(:below_threshold) { create_event("below", "Barely relevant note", 2.days.ago) }
  let!(:used_event) { create_event("used", "Already used note", 3.hours.ago) }

  let!(:ce_old_high) { channel.channel_events.create!(event: old_high, relevance_score: 95, used: false) }
  let!(:ce_mid) { channel.channel_events.create!(event: mid, relevance_score: 80, used: false) }
  let!(:ce_new_low) { channel.channel_events.create!(event: new_low, relevance_score: 60, used: false) }
  let!(:ce_below) { channel.channel_events.create!(event: below_threshold, relevance_score: 10, used: false) }
  let!(:ce_used) { channel.channel_events.create!(event: used_event, relevance_score: 90, used: true, used_at: 1.hour.ago) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  describe "GET /channels/:id" do
    it "sorts by relevance by default" do
      get channel_path(channel)

      expect(response).to have_http_status(:ok)
      expect(rendered_event_ids).to eq([old_high.id, mid.id, new_low.id])
    end

    it "falls back to relevance for an unknown sort value" do
      get channel_path(channel, sort: "relevance_score DESC; DROP TABLE events")

      expect(response).to have_http_status(:ok)
      expect(rendered_event_ids).to eq([old_high.id, mid.id, new_low.id])
    end

    it "sorts newest first" do
      get channel_path(channel, sort: "newest")

      expect(response).to have_http_status(:ok)
      expect(rendered_event_ids).to eq([new_low.id, mid.id, old_high.id])
    end

    it "sorts oldest first" do
      get channel_path(channel, sort: "oldest")

      expect(response).to have_http_status(:ok)
      expect(rendered_event_ids).to eq([old_high.id, mid.id, new_low.id])
    end

    it "still honours the relevance threshold when sorted by recency" do
      # below_threshold is newer than old_high and mid, so an unfiltered recency
      # sort would surface it near the top.
      get channel_path(channel, sort: "newest")

      expect(rendered_event_ids).not_to include(below_threshold.id)
    end

    it "hides used events when sorted by recency and Show used is off" do
      # used_event is the newest of all, so it would lead the list if the
      # unused filter were dropped.
      get channel_path(channel, sort: "newest")

      expect(rendered_event_ids).not_to include(used_event.id)
    end

    it "keeps used events at the bottom when Show used is on and sorted by recency" do
      get channel_path(channel, sort: "newest", show_used: "true")

      expect(rendered_event_ids).to eq([new_low.id, mid.id, old_high.id, used_event.id])
    end

    it "keeps used events at the bottom when Show used is on and sorted oldest first" do
      get channel_path(channel, sort: "oldest", show_used: "true")

      expect(rendered_event_ids).to eq([old_high.id, mid.id, new_low.id, used_event.id])
    end

    it "combines the recency sort with the search filter" do
      get channel_path(channel, sort: "newest", search: "note")

      expect(rendered_event_ids).to eq([new_low.id, mid.id, old_high.id])
    end

    it "carries the sort through the Show used toggle link" do
      get channel_path(channel, sort: "newest")

      # The href lands in HTML, so & is escaped.
      expect(response.body).to include(CGI.escapeHTML(channel_path(channel, show_used: true, sort: "newest")))
    end

    it "drops the sort param from the default Rating link" do
      get channel_path(channel, sort: "newest")

      expect(response.body).to include(">Rating</a>")
      expect(response.body).not_to include("sort=relevance")
    end

    it "carries the sort through the pagination links" do
      # Pagination + sort is the pairing that breaks quietly: page 2 rendered in
      # the default order would look like the sort had simply been forgotten.
      stub_const("ChannelsController::PER_PAGE", 2)

      get channel_path(channel, sort: "newest")

      expect(rendered_event_ids).to eq([new_low.id, mid.id])
      expect(response.body).to include(CGI.escapeHTML(channel_path(channel, page: 2, sort: "newest")))
    end
  end

  describe "bulk actions" do
    it "redirects back to the sorted view" do
      post bulk_mark_used_channel_path(channel), params: { event_ids: [mid.id].to_json, sort: "newest" }

      expect(response).to redirect_to(channel_path(channel, show_used: nil, sort: "newest"))
    end

    it "ignores an unknown sort value on the redirect" do
      post bulk_mark_used_channel_path(channel), params: { event_ids: [mid.id].to_json, sort: "bogus" }

      expect(response).to redirect_to(channel_path(channel, show_used: nil))
    end
  end

  def create_event(external_id, content, published_at)
    source.events.create!(
      external_id: external_id,
      content: content,
      event_type: :original,
      published_at: published_at
    )
  end

  # The event list renders one <li id="event-<id>"> per card, in display order.
  def rendered_event_ids
    response.body.scan(/id="event-(\d+)"/).flatten.map(&:to_i)
  end
end
