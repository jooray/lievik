# frozen_string_literal: true

require "rails_helper"

# The app API counterpart of spec/requests/cross_user_event_access_spec.rb.
# Ids are sequential integers, so every endpoint that takes one must resolve
# it through the caller's own records: another user's record is a 404 (never a
# read, never a write), and foreign ids inside a list are ignored.
RSpec.describe "App API cross-user isolation", type: :request do
  include ActiveJob::TestHelper

  let!(:owner) { api_user("owner", "1") }
  let!(:stranger) { api_user("stranger", "2") }
  let(:token) { api_token_for(owner) }

  let!(:owner_source) { owner.sources.create!(source_type: :rss, identifier: "https://owner.example/feed", name: "Owner feed") }
  let!(:foreign_source) { stranger.sources.create!(source_type: :rss, identifier: "https://stranger.example/feed", name: "Stranger feed") }
  let!(:owner_event) { owner_source.events.create!(external_id: "o1", content: "Owner note", published_at: 1.day.ago) }
  let!(:foreign_event) { foreign_source.events.create!(external_id: "s1", content: "SECRET-STRANGER-CONTENT", published_at: 1.day.ago) }
  let!(:owner_channel) { owner.channels.create!(name: "Mine", language: "en", prompt: "x") }
  let!(:foreign_channel) { stranger.channels.create!(name: "Theirs", language: "en", prompt: "x") }
  let!(:foreign_channel_event) { foreign_channel.channel_events.create!(event: foreign_event, relevance_score: 90) }
  let!(:owner_channel_event) { owner_channel.channel_events.create!(event: owner_event, relevance_score: 90) }
  let!(:foreign_content) { foreign_channel.channel_contents.create!(user: stranger, title: "Theirs", content: "SECRET-STRANGER-DRAFT") }
  let!(:foreign_log) { ActivityLog.create!(user: stranger, activity_type: "rating", status: :running, metadata: { "channel_id" => foreign_channel.id }) }
  let!(:foreign_token) { ApiToken.generate(stranger, name: "theirs") }

  before do
    clear_enqueued_jobs
    allow_any_instance_of(Ai::RatingService).to receive(:rate_event).and_return(score: 90, reason: "ok")
  end

  def expect_not_found
    expect(response).to have_http_status(:not_found), "#{request.method} #{request.path} answered #{response.status}"
    expect(json["code"]).to eq("not_found")
    expect(response.body).not_to include("SECRET-STRANGER")
  end

  it "404s every endpoint addressed by another user's id" do
    requests = [
      [ :get, "/api/v1/sources/#{foreign_source.id}" ],
      [ :get, "/api/v1/sources/#{foreign_source.id}/events" ],
      [ :patch, "/api/v1/sources/#{foreign_source.id}", { source: { name: "pwned" } } ],
      [ :delete, "/api/v1/sources/#{foreign_source.id}" ],
      [ :post, "/api/v1/sources/#{foreign_source.id}/refresh" ],
      [ :get, "/api/v1/channels/#{foreign_channel.id}" ],
      [ :patch, "/api/v1/channels/#{foreign_channel.id}", { channel: { name: "pwned" } } ],
      [ :delete, "/api/v1/channels/#{foreign_channel.id}" ],
      [ :post, "/api/v1/channels/#{foreign_channel.id}/rate" ],
      [ :get, "/api/v1/channels/#{foreign_channel.id}/events" ],
      [ :post, "/api/v1/channels/#{foreign_channel.id}/events/mark_used", { event_ids: [ foreign_event.id ] } ],
      [ :post, "/api/v1/channels/#{foreign_channel.id}/events/mark_unused", { event_ids: [ foreign_event.id ] } ],
      [ :post, "/api/v1/channels/#{foreign_channel.id}/events/rate", { event_ids: [ foreign_event.id ] } ],
      [ :get, "/api/v1/channels/#{foreign_channel.id}/contents" ],
      [ :post, "/api/v1/channels/#{foreign_channel.id}/contents", { channel_content: { title: "x" } } ],
      [ :get, "/api/v1/channels/#{foreign_channel.id}/contents/#{foreign_content.id}" ],
      [ :get, "/api/v1/channels/#{owner_channel.id}/contents/#{foreign_content.id}" ],
      [ :patch, "/api/v1/channels/#{owner_channel.id}/contents/#{foreign_content.id}", { channel_content: { content: "pwned" } } ],
      [ :delete, "/api/v1/channels/#{owner_channel.id}/contents/#{foreign_content.id}" ],
      [ :post, "/api/v1/channels/#{owner_channel.id}/contents/#{foreign_content.id}/generate" ],
      [ :post, "/api/v1/channels/#{owner_channel.id}/contents/#{foreign_content.id}/refine", { user_prompt: "x" } ],
      [ :post, "/api/v1/channels/#{owner_channel.id}/contents/#{foreign_content.id}/publish" ],
      [ :post, "/api/v1/channels/#{owner_channel.id}/contents/#{foreign_content.id}/revert" ],
      [ :get, "/api/v1/events/#{foreign_event.id}" ],
      [ :post, "/api/v1/events/#{foreign_event.id}/mark_used", { channel_event_ids: [ foreign_channel_event.id ] } ],
      [ :get, "/api/v1/activity_logs/#{foreign_log.id}/dev_logs" ],
      [ :post, "/api/v1/activity_logs/#{foreign_log.id}/cancel" ],
      [ :post, "/api/v1/activity_logs/#{foreign_log.id}/retry" ],
      [ :delete, "/api/v1/api_tokens/#{foreign_token.id}" ]
    ]

    requests.each do |verb, path, params|
      public_send(:"api_#{verb}", path, token, params: params)
      expect_not_found
    end

    expect(foreign_source.reload.name).to eq("Stranger feed")
    expect(foreign_channel.reload.name).to eq("Theirs")
    expect(foreign_content.reload.content).to eq("SECRET-STRANGER-DRAFT")
    expect(foreign_channel_event.reload.used).to be(false)
    expect(foreign_log.reload).to be_running
    expect(ApiToken.exists?(foreign_token.id)).to be(true)
    expect(ChannelContent.where(channel: foreign_channel).count).to eq(1)
    expect(RateEventsJob).not_to have_been_enqueued
    expect(SourceIngestionJob).not_to have_been_enqueued
  end

  it "ignores another user's event ids inside the caller's own channel" do
    perform_enqueued_jobs do
      api_post "/api/v1/channels/#{owner_channel.id}/events/rate", token, params: { event_ids: [ foreign_event.id ] }
    end
    expect(response).to have_http_status(:unprocessable_content)
    expect(ChannelEvent.where(channel: owner_channel, event: foreign_event)).to be_empty

    perform_enqueued_jobs do
      api_post "/api/v1/events/rate", token, params: { event_ids: [ owner_event.id, foreign_event.id ] }
    end
    expect(response).to have_http_status(:ok)
    expect(json["count"]).to eq(1)
    expect(ChannelEvent.where(event: foreign_event).where.not(channel: foreign_channel)).to be_empty
  end

  it "does not flip another user's channel_events through the caller's own event" do
    api_post "/api/v1/events/#{owner_event.id}/mark_used", token, params: { channel_event_ids: [ foreign_channel_event.id ] }

    expect(json["count"]).to eq(0)
    expect(foreign_channel_event.reload.used).to be(false)
  end

  it "does not attach another user's events to a new draft" do
    api_post "/api/v1/channels/#{owner_channel.id}/contents", token,
             params: { channel_content: { title: "Draft" }, event_ids: [ foreign_event.id, owner_event.id ] }

    expect(response).to have_http_status(:created)
    expect(json.dig("content", "event_ids")).to eq([ owner_event.id ])
  end

  it "never lists or syncs another user's records" do
    %w[/api/v1/sources /api/v1/channels /api/v1/events /api/v1/dashboard /api/v1/sync /api/v1/activity_logs /api/v1/api_tokens].each do |path|
      api_get path, token
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("SECRET-STRANGER")
      expect(response.body).not_to include("Stranger feed")
    end

    api_get "/api/v1/events", token, params: { source_id: foreign_source.id }
    expect(json["events"]).to be_empty
  end

  it "only cites the caller's events in chat" do
    allow_any_instance_of(Rag::ChatService).to receive(:chat_stream).and_return(success: true, cited_event_ids: [ foreign_event.id, owner_event.id ])

    api_post "/api/v1/chat/stream", token, params: { question: "anything" }

    complete = sse_events.find { |name, _| name == "complete" }
    expect(complete.last["cited_events"].map { |e| e["id"] }).to eq([ owner_event.id ])
  end

  it "only polls billing charges the caller created through the API" do
    stub_billing
    api_post "/api/v1/billing/charges", token, params: { plan: "lievik" }
    own_invoice = json["invoice_id"]

    other = api_token_for(stranger)
    api_get "/api/v1/billing/charges/#{own_invoice}", other
    expect(response).to have_http_status(:not_found)

    api_get "/api/v1/billing/charges/#{own_invoice}", token
    expect(response).to have_http_status(:ok)
  end
end
