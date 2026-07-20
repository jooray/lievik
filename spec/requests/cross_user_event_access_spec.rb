# frozen_string_literal: true

require "rails_helper"

# Regression cover for the cross-user `event_ids` scoping fix: every endpoint that
# accepts caller-supplied event ids must resolve them through `current_user.events`
# so another user's events can never be rated into, or rendered inside, our channel.
RSpec.describe "Cross-user event_ids scoping", type: :request do
  include ActiveJob::TestHelper

  let!(:owner) { create_user("owner", "1") }
  let!(:stranger) { create_user("stranger", "2") }

  let!(:owner_source) { create_source(owner, "owner-src") }
  let!(:stranger_source) { create_source(stranger, "stranger-src") }

  let!(:owner_event) { create_event(owner_source, "owner-evt", "Owner's own note about bitcoin") }
  let!(:foreign_event) { create_event(stranger_source, "stranger-evt", "SECRET-STRANGER-CONTENT") }

  let!(:channel) { owner.channels.create!(name: "Newsletter", language: "en", prompt: "anything") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(owner)
    # Any event that does get rated is scored deterministically, no network.
    allow_any_instance_of(Ai::RatingService).to receive(:rate_event).and_return(score: 90, reason: "ok")
  end

  describe "POST /channels/:id/bulk_rate" do
    it "does not create a ChannelEvent for another user's event" do
      perform_enqueued_jobs do
        post bulk_rate_channel_path(channel), params: { event_ids: [foreign_event.id].to_json }
      end

      expect(ChannelEvent.where(event_id: foreign_event.id)).to be_empty
      expect(response).to redirect_to(channel_path(channel, show_used: nil))
    end

    it "rates only the caller's own events when the ids are mixed" do
      perform_enqueued_jobs do
        post bulk_rate_channel_path(channel), params: { event_ids: [owner_event.id, foreign_event.id].to_json }
      end

      expect(ChannelEvent.where(event_id: foreign_event.id)).to be_empty
      expect(ChannelEvent.where(channel: channel, event: owner_event)).to exist
    end
  end

  describe "POST /events/bulk_rate" do
    it "does not create a ChannelEvent for another user's event" do
      perform_enqueued_jobs do
        post bulk_rate_events_path, params: { event_ids: [foreign_event.id] }
      end

      expect(ChannelEvent.where(event_id: foreign_event.id)).to be_empty
    end

    it "rates only the caller's own events when the ids are mixed" do
      perform_enqueued_jobs do
        post bulk_rate_events_path, params: { event_ids: [owner_event.id, foreign_event.id] }
      end

      expect(ChannelEvent.where(event_id: foreign_event.id)).to be_empty
      expect(ChannelEvent.where(channel: channel, event: owner_event)).to exist
    end
  end

  describe "RateEventsJob" do
    it "ignores event ids outside the channel owner's sources" do
      RateEventsJob.perform_now(channel.id, [foreign_event.id])

      expect(ChannelEvent.where(event_id: foreign_event.id)).to be_empty
    end
  end

  describe "GET /channels/:id/contents/new" do
    it "does not render another user's event content" do
      get new_channel_content_path(channel, event_ids: [foreign_event.id].to_json)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("SECRET-STRANGER-CONTENT")
      expect(response.body).to include("No events selected")
    end

    it "renders the caller's own event content" do
      get new_channel_content_path(channel, event_ids: [owner_event.id].to_json)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owner&#39;s own note about bitcoin")
    end
  end

  describe "POST /channels/:id/contents" do
    it "does not attach another user's event to the created content" do
      post channel_contents_path(channel), params: {
        channel_content: { title: "Draft" },
        event_ids: [foreign_event.id].to_json
      }

      content = ChannelContent.order(:created_at).last
      expect(content).to be_present
      expect(content.events).to be_empty
    end
  end

  def create_user(name, digit)
    User.create!(npub: "npub1#{name}", pubkey_hex: digit * 64, display_name: name)
  end

  def create_source(user, identifier)
    user.sources.create!(source_type: :manual, identifier: identifier, name: identifier, distance: 5)
  end

  def create_event(source, external_id, content)
    source.events.create!(
      external_id: external_id,
      content: content,
      event_type: :original,
      published_at: 1.day.ago
    )
  end
end
