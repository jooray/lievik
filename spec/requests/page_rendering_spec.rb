# frozen_string_literal: true

require "rails_helper"

# Full-app render smoke test for the audit-remediation pass: many controllers had
# grouped COUNT queries moved out of views and into new ivars, plus a new
# per-request nostr-reference memoization layer, deleted routes/actions, and a new
# PWA layer. There was almost no view-render coverage, so a typo in an ivar name
# would only surface in production. This hits every primary page with realistic,
# varied data and asserts a clean 200 render.
#
# Uses the same current_user stubbing approach as
# spec/requests/cross_user_event_access_spec.rb (allow_any_instance_of on
# ApplicationController), plus local create_user/create_source/create_event
# helpers mirroring that file.
RSpec.describe "Page rendering", type: :request do
  describe "Unauthenticated pages" do
    it "renders the public landing page" do
      get root_path

      expect(response).to have_http_status(:ok)
    end

    it "renders the Nostr login page" do
      get nostr_login_path

      expect(response).to have_http_status(:ok)
    end

    it "renders the PWA manifest" do
      get pwa_manifest_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "renders the version endpoint" do
      get app_version_path

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("version")
    end

    it "renders the service worker" do
      get pwa_service_worker_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "Authenticated pages" do
    # --- Users / sources -----------------------------------------------------
    let!(:user) { create_user("owner", "1") }

    let(:npub_a) { Nostr::KeyConverter.hex_to_npub("a" * 64) }

    let!(:source_a) do
      user.sources.create!(source_type: :nostr, identifier: npub_a, name: "Source A", distance: 3)
    end
    let!(:source_b) do
      user.sources.create!(source_type: :rss, identifier: "https://example.com/feed.xml", name: "Source B", distance: 5)
    end

    # --- Events (several, across both sources, one with a nostr: reference) --
    let!(:event1) { create_event(source_a, "evt-1", "Plain original note about privacy tools", type: :original, published_at: 1.day.ago) }
    let!(:event2) { create_event(source_a, "evt-2", "A reply about the same topic", type: :reply, published_at: 2.days.ago) }
    let!(:event3) do
      create_event(source_b, "evt-3", "Check this out nostr:#{npub_a} said something interesting",
        type: :original, published_at: 3.days.ago)
    end
    let!(:event4) { create_event(source_b, "evt-4", "A reposted announcement", type: :repost, published_at: 4.days.ago) }

    # --- Channels + ChannelEvents at varying relevance_score, incl. NULL -----
    # (a NULL relevance_score used to 500 the dashboard — regression cover)
    let!(:channel1) { user.channels.create!(name: "Newsletter", language: "en", prompt: "Rate privacy content highly") }
    let!(:channel2) { user.channels.create!(name: "Signal Group", language: "en", prompt: "Rate anything Bitcoin-related") }

    let!(:ce1) { channel1.channel_events.create!(event: event1, relevance_score: 90, used: false) }
    let!(:ce2) { channel1.channel_events.create!(event: event2, relevance_score: 65, used: true, used_at: 1.hour.ago) }
    let!(:ce3) { channel2.channel_events.create!(event: event3, relevance_score: nil, used: false) }
    let!(:ce4) { channel2.channel_events.create!(event: event1, relevance_score: 75, used: false) }

    # --- ActivityLog + DevLogs ------------------------------------------------
    let!(:activity_log1) do
      user.activity_logs.create!(activity_type: "ingestion", status: "completed", message: "Imported 4 events", completed_at: Time.current)
    end
    let!(:dev_log1) { DevLog.create!(user: user, parent: activity_log1, log_type: "ingestion_event", message: "Ingested evt-1") }
    let!(:dev_log2) { DevLog.create!(user: user, parent: activity_log1, log_type: "ingestion_error", message: "Failed to parse an entry") }
    let!(:activity_log2) do
      log = user.activity_logs.create!(activity_type: "rating", status: "running", message: "Rating channel Newsletter")
      log.update_column(:updated_at, 20.minutes.ago) # also exercises the "stale job" branch
      log
    end

    # --- ChannelContent with attached events (draft + published) ------------
    let!(:content_draft) do
      content = channel1.channel_contents.create!(
        user: user, title: "Draft Newsletter", content: "Draft body text",
        generation_prompt: "Focus on privacy", status: :draft
      )
      content.channel_content_events.create!(event: event1)
      content.channel_content_events.create!(event: event2)
      content
    end
    let!(:content_published) do
      content = channel1.channel_contents.create!(
        user: user, title: "Published Newsletter", content: "Published body text",
        status: :published, published_at: 2.hours.ago
      )
      content.channel_content_events.create!(event: event3)
      content
    end

    before do
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)

      # Nothing in this suite performs enqueued jobs, so none of these are
      # actually reachable from a GET — stubbed anyway per the no-network policy
      # for this suite, so any future code path added to one of these pages can
      # never make it out to the real network from here.
      allow_any_instance_of(Ai::RatingService).to receive(:rate_event).and_return(score: 90, reason: "stubbed")
      allow_any_instance_of(Nostr::ProfileFetcher).to receive(:fetch).and_return(nil)
      allow_any_instance_of(Nostr::ProfileFetcher).to receive(:fetch_event).and_return(nil)
      allow_any_instance_of(Rag::EmbeddingService).to receive(:embed).and_return(nil)
      allow(Security::EgressGuard).to receive(:filter_relay_urls).and_return([])
    end

    describe "GET /dashboard" do
      it "renders with mixed relevance scores, incl. a NULL one, and resolves the nostr: reference" do
        get dashboard_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("@Source A")
      end
    end

    describe "GET /sources" do
      it "renders the index with grouped per-source event counts" do
        get sources_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Source A").and include("Source B")
      end

      it "renders a source's show page" do
        get source_path(source_a)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Source A")
      end

      it "renders the new source form" do
        get new_source_path

        expect(response).to have_http_status(:ok)
      end

      it "renders the edit source form" do
        get edit_source_path(source_a)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /channels" do
      it "renders the index with grouped pending-event counts" do
        get channels_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Newsletter").and include("Signal Group")
      end

      it "renders a channel's show page with used and unused events" do
        get channel_path(channel1)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("90%")
      end

      it "renders the new channel form" do
        get new_channel_path

        expect(response).to have_http_status(:ok)
      end

      it "renders the edit channel form" do
        get edit_channel_path(channel1)

        expect(response).to have_http_status(:ok)
      end

      it "renders the channel settings page" do
        get settings_channel_path(channel1)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /events" do
      it "renders the index" do
        get events_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("evt-1").or include("Plain original note")
      end

      it "renders an event's show page, incl. one with a NULL relevance_score" do
        get event_path(event3)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("@Source A")
      end
    end

    describe "GET /activity_logs" do
      it "renders the index with active/stale jobs and grouped dev-log counts" do
        get activity_logs_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Imported 4 events")
        expect(response.body).to include("Dev Log")
      end
    end

    describe "GET /user/edit" do
      it "renders settings with precomputed search-index stats" do
        get edit_user_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("of").and include("events indexed")
      end
    end

    describe "channel contents" do
      it "renders the index (drafts + published, grouped event counts)" do
        get channel_contents_path(channel1)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Draft Newsletter").and include("Published Newsletter")
      end

      it "renders the new content form for selected events" do
        get new_channel_content_path(channel1, event_ids: [event1.id].to_json)

        expect(response).to have_http_status(:ok)
      end

      it "renders a published content's show page" do
        get channel_content_path(channel1, content_published)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Published Newsletter")
      end

      it "renders a draft content's edit page" do
        get edit_channel_content_path(channel1, content_draft)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Draft Newsletter")
      end
    end

    describe "GET /chat (RAG chat page)" do
      it "renders" do
        get rag_chat_path

        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /channels/ai (AI channel chat page)" do
      it "renders" do
        get channel_ai_chat_path

        expect(response).to have_http_status(:ok)
      end
    end
  end

  def create_user(name, digit)
    User.create!(npub: "npub1#{name}", pubkey_hex: digit * 64, display_name: name)
  end

  def create_source(user, identifier)
    user.sources.create!(source_type: :manual, identifier: identifier, name: identifier, distance: 5)
  end

  def create_event(source, external_id, content, type: :original, published_at: 1.day.ago)
    source.events.create!(
      external_id: external_id,
      content: content,
      event_type: type,
      published_at: published_at
    )
  end
end
