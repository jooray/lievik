# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App API resources", type: :request do
  include ActiveJob::TestHelper

  let!(:user) { api_user }
  let(:token) { api_token_for(user) }

  before { clear_enqueued_jobs }

  describe "GET /api/v1/meta" do
    it "needs no token and reads the Android version gate from the environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANDROID_MIN_VERSION_CODE").and_return("3")
      allow(ENV).to receive(:[]).with("ANDROID_LATEST_VERSION_CODE").and_return("5")
      allow(ENV).to receive(:[]).with("ANDROID_DOWNLOAD_URL").and_return("https://example.com/lievik.apk")

      get "/api/v1/meta"

      expect(response).to have_http_status(:ok)
      expect(json).to include("api_version" => 1, "billing_enabled" => false, "locales" => %w[en sk cs es])
      expect(json["android"]).to eq("min_version_code" => 3, "latest_version_code" => 5, "download_url" => "https://example.com/lievik.apk")
      expect(json["nip46_relays"]).to be_present
    end
  end

  describe "locale" do
    it "translates notices from ?locale=, then Accept-Language, then the user's setting" do
      user.update!(locale: "cs")
      api_post "/api/v1/me/reindex", token, locale: "sk"
      expect(json["notice"]).to eq(I18n.t("users.reindex.notice", locale: :sk))

      api_post "/api/v1/me/reindex?locale=es", token, locale: "sk"
      expect(json["notice"]).to eq(I18n.t("users.reindex.notice", locale: :es))

      api_post "/api/v1/me/reindex", token
      expect(json["notice"]).to eq(I18n.t("users.reindex.notice", locale: :cs))
      expect(user.reload.locale).to eq("cs")
    end
  end

  describe "me" do
    it "shows the user with stats and billing, and updates settings" do
      api_get "/api/v1/me", token
      expect(json["user"]["settings"]).to include("rating_engine" => "chat", "event_link_template" => User::DEFAULT_EVENT_LINK_TEMPLATE)
      expect(json["stats"]).to eq("sources" => 0, "channels" => 0, "events" => 0, "embedded" => 0)

      api_patch "/api/v1/me", token, params: { user: { locale: "sk", event_link_template: "https://njump.me/{eventid}", npub: "npub1evil" } }
      expect(response).to have_http_status(:ok)
      expect(json["notice"]).to eq(I18n.t("users.update.notice", locale: :sk))
      expect(user.reload.locale).to eq("sk")
      expect(user.event_link_template).to eq("https://njump.me/{eventid}")
      expect(user.npub).to eq("npub1user")
    end

    it "answers 400 when the wrapper object is missing" do
      api_patch "/api/v1/me", token, params: { locale: "sk" }
      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("bad_request")
    end
  end

  describe "templates" do
    it "adds, updates and deletes by index" do
      api_post "/api/v1/templates", token, params: { name: "Digest", template: "# D" }
      expect(response).to have_http_status(:created)

      api_patch "/api/v1/templates/0", token, params: { template: "# Digest" }
      expect(json["template"]).to eq("index" => 0, "name" => "Digest", "template" => "# Digest")

      api_get "/api/v1/templates", token
      expect(json["templates"].size).to eq(1)
      expect(json["defaults"].map { |t| t["name"] }).to include("Newsletter")

      api_delete "/api/v1/templates/5", token
      expect(response).to have_http_status(:not_found)
      api_delete "/api/v1/templates/0", token
      expect(user.reload.content_templates_list).to be_empty
    end
  end

  describe "api tokens" do
    it "lists tokens with the current one marked and creates a new one" do
      token
      api_post "/api/v1/api_tokens", token, params: { name: "agent" }
      expect(response).to have_http_status(:created)
      expect(json["plain_token"]).to start_with("lvk_")

      api_get "/api/v1/api_tokens", token
      expect(json["api_tokens"].map { |t| [ t["name"], t["current"] ] }).to match_array([ [ "spec", true ], [ "agent", false ] ])

      api_post "/api/v1/api_tokens", token, params: { name: " " }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "sources" do
    it "creates a source, queues ingestion and reports validation errors per field" do
      api_post "/api/v1/sources", token, params: { source: { source_type: "rss", identifier: "https://blog.example/feed", name: "Blog" } }
      expect(response).to have_http_status(:created)
      expect(json).to include("notice" => I18n.t("sources.create.importing"), "importing" => true)
      expect(json["source"]).to include("source_type" => "rss", "event_count" => 0)
      expect(SourceIngestionJob).to have_been_enqueued

      api_post "/api/v1/sources", token, params: { source: { source_type: "nostr", identifier: "npub1garbage", distance: 42 } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("invalid")
      expect(json["details"].keys).to match_array(%w[identifier distance])

      api_get "/api/v1/sources", token
      expect(json["sources"].map { |s| s["name"] }).to eq([ "Blog" ])
    end

    it "refuses to refresh a manual source" do
      api_post "/api/v1/sources/#{user.sources.manual.first.id}/refresh", token
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq(I18n.t("sources.refresh.unsupported"))
    end
  end

  describe "channels" do
    it "creates with initial rating, merges settings on update and validates" do
      user.sources.manual.first.events.create!(external_id: "x", content: "recent", published_at: 1.day.ago)

      api_get "/api/v1/channels/new", token
      expect(json.dig("channel", "prompt")).to eq(Channel.default_prompt_template)

      api_post "/api/v1/channels", token, params: { channel: { name: "News", language: "en", prompt: "p" } }
      expect(response).to have_http_status(:created)
      expect(json).to include("queued" => 1, "notice" => I18n.t("channels.create.notice_queued", count: 1))
      id = json.dig("channel", "id")

      api_patch "/api/v1/channels/#{id}", token, params: { channel: { content_style: "short", settings: { humanize_output: false } } }
      expect(json.dig("channel", "settings")).to eq("relevance_threshold" => 50, "humanize_output" => false)
      api_patch "/api/v1/channels/#{id}", token, params: { channel: { settings: { relevance_threshold: "70" } } }
      expect(json.dig("channel", "settings")).to eq("relevance_threshold" => 70, "humanize_output" => false)

      api_patch "/api/v1/channels/#{id}", token, params: { channel: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["details"]).to have_key("name")
    end
  end

  describe "channel events" do
    let!(:channel) { user.channels.create!(name: "News", language: "en", prompt: "x", settings: { "relevance_threshold" => 50 }) }
    let(:src) { user.sources.manual.first }
    let!(:high) { src.events.create!(external_id: "h", content: "high bitcoin", published_at: 2.days.ago) }
    let!(:mid) { src.events.create!(external_id: "m", content: "mid", published_at: 1.day.ago) }
    let!(:low) { src.events.create!(external_id: "l", content: "low", published_at: 1.hour.ago) }

    before do
      channel.channel_events.create!(event: high, relevance_score: 90)
      channel.channel_events.create!(event: mid, relevance_score: 60)
      channel.channel_events.create!(event: low, relevance_score: 10)
    end

    it "lists like the web channel page and marks used/unused" do
      api_get "/api/v1/channels/#{channel.id}/events", token
      expect(json["items"].map { |i| i.dig("event", "id") }).to eq([ high.id, mid.id ])
      expect(json).to include("used_count" => 0, "unused_count" => 2, "threshold" => 50)
      expect(json["items"].first["channel_event"]).to include("relevance_score" => 90, "used" => false)

      api_get "/api/v1/channels/#{channel.id}/events", token, params: { sort: "newest" }
      expect(json["items"].map { |i| i.dig("event", "id") }).to eq([ mid.id, high.id ])

      api_get "/api/v1/channels/#{channel.id}/events", token, params: { search: "bitcoin" }
      expect(json["items"].size).to eq(1)

      api_post "/api/v1/channels/#{channel.id}/events/mark_used", token, params: { event_ids: [ high.id ] }
      expect(json).to eq("notice" => I18n.t("channel_events.bulk_mark_used.notice", count: 1), "count" => 1)

      api_get "/api/v1/channels/#{channel.id}/events", token
      expect(json["items"].size).to eq(1)
      api_get "/api/v1/channels/#{channel.id}/events", token, params: { show_used: true }
      expect(json["items"].map { |i| i.dig("channel_event", "used") }).to eq([ false, true ])

      api_post "/api/v1/channels/#{channel.id}/events/mark_unused", token, params: { event_ids: [ high.id ] }
      expect(json["count"]).to eq(1)
      expect(ChannelEvent.find_by(event: high).used).to be(false)

      api_post "/api/v1/channels/#{channel.id}/events/mark_used", token, params: { event_ids: [] }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq(I18n.t("channel_events.no_selection"))
    end

    it "pages with meta" do
      api_get "/api/v1/channels/#{channel.id}/events", token, params: { per: 1, page: 2 }
      expect(json["meta"]).to eq("page" => 2, "per" => 1, "total_pages" => 2, "total_count" => 2)
      expect(json["items"].map { |i| i.dig("event", "id") }).to eq([ mid.id ])
    end
  end

  describe "contents" do
    let!(:channel) { user.channels.create!(name: "News", language: "en", prompt: "x") }

    it "creates, saves versions, publishes and reverts" do
      api_post "/api/v1/channels/#{channel.id}/contents", token, params: { channel_content: { title: "Issue 1" } }
      expect(response).to have_http_status(:created)
      id = json.dig("content", "id")

      api_post "/api/v1/channels/#{channel.id}/contents/#{id}/revert", token
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("no_previous")

      api_patch "/api/v1/channels/#{channel.id}/contents/#{id}", token, params: { channel_content: { content: "v1" } }
      api_patch "/api/v1/channels/#{channel.id}/contents/#{id}", token, params: { channel_content: { content: "v2" } }
      expect(json.dig("content", "versions_count")).to eq(1)

      api_post "/api/v1/channels/#{channel.id}/contents/#{id}/revert", token
      expect(json.dig("content", "content")).to eq("v1")

      api_post "/api/v1/channels/#{channel.id}/contents/#{id}/publish", token
      expect(json.dig("content", "status")).to eq("published")

      api_get "/api/v1/channels/#{channel.id}/contents", token
      expect(json["published"].map { |c| c["id"] }).to eq([ id ])
      expect(json["drafts"]).to be_empty
    end
  end

  describe "events" do
    let!(:nostr_source) do
      user.sources.create!(source_type: :nostr, identifier: Nostr::KeyConverter.hex_to_npub("a" * 64), name: "Alice")
    end

    it "serializes author, images, references and top channels" do
      referenced = nostr_source.events.create!(external_id: "b" * 64, content: "The referenced note", published_at: 2.days.ago,
                                               raw_data: { "pubkey" => "a" * 64, "kind" => 1 })
      nevent = Nostr::KeyConverter.hex_to_nevent("b" * 64)
      npub = Nostr::KeyConverter.hex_to_npub("a" * 64)
      content = "Look https://img.example/cat.JPG?w=1 and nostr:#{nevent} by nostr:#{npub} https://example.com/page"
      event = nostr_source.events.create!(
        external_id: "c" * 64, content: content, published_at: 1.day.ago,
        raw_data: { "pubkey" => "a" * 64, "kind" => 1, "tags" => [ [ "imeta", "url https://img.example/dog", "m image/png" ] ] }
      )
      channel = user.channels.create!(name: "News", language: "en", prompt: "x")
      channel.channel_events.create!(event: event, relevance_score: 77)
      User.create!(npub: npub, pubkey_hex: "a" * 64, picture_url: "https://img.example/alice.png")

      api_get "/api/v1/events/#{event.id}", token
      body = json["event"]

      expect(body).to include("source_name" => "Alice", "source_type" => "nostr", "kind" => 1, "event_type" => "original")
      expect(body["author"]).to eq("name" => "Alice", "picture_url" => "https://img.example/alice.png", "npub" => npub)
      expect(body["images"]).to eq([ "https://img.example/cat.JPG?w=1", "https://img.example/dog" ])
      expect(body["source_url"]).to start_with("https://yakihonne.com/note/nevent1")
      expect(body["nostr_uri"]).to eq("nostr:#{event.nevent_id}")
      expect(body["references"]).to eq([
        { "uri" => "nostr:#{nevent}", "type" => "event", "label" => "Alice", "preview" => "The referenced note",
          "url" => "https://yakihonne.com/note/#{nevent}" },
        { "uri" => "nostr:#{npub}", "type" => "profile", "label" => "@Alice", "url" => "https://yakihonne.com/profile/#{npub}", "npub" => npub }
      ])
      expect(body["top_channels"]).to eq([ { "channel_id" => channel.id, "channel_name" => "News", "relevance_score" => 77, "used" => false } ])
      expect(json["channel_events"].first).to include("channel_name" => "News", "relevance_score" => 77)
    end

    it "filters the list and exposes the filter sources" do
      nostr_source.events.create!(external_id: "d" * 64, content: "reply text", event_type: :reply, published_at: 1.day.ago)
      user.sources.manual.first.events.create!(external_id: "m", content: "manual text", published_at: 1.day.ago)

      api_get "/api/v1/events", token, params: { event_type: "reply" }
      expect(json["events"].map { |e| e["content"] }).to eq([ "reply text" ])
      expect(json["filter_sources"].map { |s| s["name"] }).to eq([ "Alice", "Manual entries" ])
      expect(json["meta"]).to include("total_count" => 1)
    end

    it "adds a manual event and rejects a blank one with field details" do
      api_post "/api/v1/manual_events", token, params: { content: "My note" }
      expect(response).to have_http_status(:created)
      expect(json).to include("notice" => I18n.t("manual_events.create.added"))
      expect(json.dig("event", "source_type")).to eq("manual")

      api_post "/api/v1/manual_events", token, params: { content: "" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["details"]).to have_key("content")
    end
  end

  describe "activity logs" do
    it "lists, polls active (sweeping stale ones) and cancels" do
      stale = ActivityLog.create!(user: user, activity_type: "rating", status: :running)
      stale.update_columns(updated_at: 1.hour.ago)
      live = ActivityLog.create!(user: user, activity_type: "ingestion", status: :running)

      api_get "/api/v1/activity_logs/active", token
      expect(json["jobs"].map { |j| j["id"] }).to eq([ live.id ])
      expect(stale.reload).to be_failed

      api_post "/api/v1/activity_logs/#{live.id}/cancel", token
      expect(json["notice"]).to eq(I18n.t("activity_logs.cancel.notice"))
      api_post "/api/v1/activity_logs/#{live.id}/cancel", token
      expect(response).to have_http_status(:unprocessable_content)

      api_post "/api/v1/activity_logs/#{live.id}/retry", token
      expect(json["error"]).to eq(I18n.t("activity_logs.retry_job.no_channel"))

      api_get "/api/v1/activity_logs", token
      expect(json["activity_logs"].size).to eq(2)
      expect(json["meta"]["total_count"]).to eq(2)
    end
  end

  describe "dashboard" do
    it "shows stats and recent events, and queues rate all" do
      user.channels.create!(name: "News", language: "en", prompt: "x")
      api_get "/api/v1/dashboard", token
      expect(json).to include("active_jobs" => [], "recent_events" => [])

      api_post "/api/v1/dashboard/rate_all", token
      expect(json).to include("queued_channels" => 1, "notice" => I18n.t("dashboard.rate_all.queued", count: 1))
      expect(RateEventsJob).to have_been_enqueued
    end
  end
end
