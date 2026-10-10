# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App API sync", type: :request do
  let!(:user) { api_user }
  let(:token) { api_token_for(user) }
  let!(:source) { user.sources.create!(source_type: :rss, identifier: "https://feed.example/rss", name: "Feed", settings_import_days: 30) }
  let!(:channel) { user.channels.create!(name: "News", language: "en", prompt: "x") }

  def make_event(n, published_at: n.hours.ago)
    source.events.create!(external_id: "e#{n}", content: "Event #{n}", published_at: published_at)
  end

  def sync(since: nil, cursor: nil)
    api_get "/api/v1/sync", token, params: { since: since, cursor: cursor }.compact
    expect(response).to have_http_status(:ok)
    json
  end

  def full_sync(since: nil)
    pages = [ sync(since: since) ]
    pages << sync(cursor: pages.last["next_cursor"]) while pages.last["next_cursor"]
    pages
  end

  it "returns everything in the window on the initial sync, newest first" do
    events = (1..3).map { |n| make_event(n) }
    old = make_event(99, published_at: 60.days.ago)
    ce = channel.channel_events.create!(event: events.first, relevance_score: 80)
    channel.channel_events.create!(event: old, relevance_score: 80)

    body = sync

    expect(body["server_time"]).to be_present
    expect(body["sources"].map { |s| s["id"] }).to include(source.id, user.sources.manual.first.id)
    expect(body["channels"].map { |c| c["id"] }).to eq([ channel.id ])
    expect(body["events"].map { |e| e["id"] }).to eq(events.map(&:id))
    expect(body["channel_events"].map { |c| c["id"] }).to eq([ ce.id ])
    expect(body["next_cursor"]).to be_nil
  end

  it "pages both streams through one cursor and repeats the first server_time" do
    stub_const("Api::V1::SyncController::EVENTS_PER_PAGE", 2)
    stub_const("Api::V1::SyncController::CHANNEL_EVENTS_PER_PAGE", 3)
    events = (1..5).map { |n| make_event(n) }
    events.each { |e| channel.channel_events.create!(event: e, relevance_score: 70) }

    pages = full_sync

    expect(pages.size).to eq(3)
    expect(pages.map { |p| p["server_time"] }.uniq.size).to eq(1)
    expect(pages.flat_map { |p| p["events"].map { |e| e["id"] } }).to eq(events.map(&:id))
    expect(pages.flat_map { |p| p["channel_events"].map { |c| c["event_id"] } }).to match_array(events.map(&:id))
    expect(pages.last["next_cursor"]).to be_nil
  end

  it "returns only what changed since the last sync, including used flags set in bulk" do
    a = make_event(1)
    b = make_event(2)
    ce_a = channel.channel_events.create!(event: a, relevance_score: 80)
    ce_b = channel.channel_events.create!(event: b, relevance_score: 80)
    since = nil

    travel_to(1.hour.ago) { since = Time.current }
    [ a, b ].each { |e| e.update_columns(updated_at: 2.hours.ago) }
    [ ce_a, ce_b ].each { |c| c.update_columns(updated_at: 2.hours.ago) }

    body = sync(since: since.iso8601)
    expect(body["events"]).to be_empty
    expect(body["channel_events"]).to be_empty

    # The web's bulk "mark as used" (update_all) must still bump updated_at.
    api_post "/api/v1/channels/#{channel.id}/events/mark_used", token, params: { event_ids: [ a.id ] }
    c = make_event(3)

    body = sync(since: since.iso8601)
    expect(body["events"].map { |e| e["id"] }).to eq([ c.id ])
    expect(body["channel_events"].map { |x| [ x["id"], x["used"] ] }).to eq([ [ ce_a.id, true ] ])
  end

  it "picks up a publish (which marks its events used) incrementally" do
    a = make_event(1)
    ce = channel.channel_events.create!(event: a, relevance_score: 80)
    ce.update_columns(updated_at: 2.hours.ago)
    content = channel.channel_contents.create!(user: user, content: "text")
    content.channel_content_events.create!(event: a)

    since = 1.hour.ago.iso8601
    content.publish!

    expect(sync(since: since)["channel_events"].map { |x| x["used"] }).to eq([ true ])
  end

  it "rejects a garbled cursor or since" do
    api_get "/api/v1/sync", token, params: { cursor: "not-a-cursor" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(json["code"]).to eq("invalid")

    api_get "/api/v1/sync", token, params: { since: "yesterday" }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
