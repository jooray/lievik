# frozen_string_literal: true

require "rails_helper"

# Web behaviour that lives in code shared with the app API.
RSpec.describe "Web actions on shared logic", type: :request do
  let!(:user) { User.create!(npub: "npub1web", pubkey_hex: "7" * 64, display_name: "Web") }
  let!(:source) { user.sources.create!(source_type: :manual, identifier: "manual", name: "Manual", distance: 1) }
  let!(:channel) { user.channels.create!(name: "News", language: "en", prompt: "x") }
  let!(:event) { source.events.create!(external_id: "e1", content: "note", published_at: 1.day.ago) }

  before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

  it "bumps updated_at when bulk marking used, so the app's sync sees it" do
    ce = channel.channel_events.create!(event: event, relevance_score: 90)
    ce.update_columns(updated_at: 1.day.ago)

    post bulk_mark_used_channel_path(channel), params: { event_ids: [ event.id ].to_json }

    expect(flash[:notice]).to eq(I18n.t("channel_events.bulk_mark_used.notice", count: 1))
    expect(ce.reload.used).to be(true)
    expect(ce.updated_at).to be > 1.minute.ago
  end

  it "turns humanizing off when the settings checkbox is unticked" do
    patch update_settings_channel_path(channel), params: { channel: { settings: { relevance_threshold: "65", humanize_output: "false" } } }

    channel.reload
    expect(channel.humanize_output?).to be(false)
    expect(channel.relevance_threshold).to eq(65)
  end

  it "links the Android app on the settings page only when a download URL is configured" do
    get edit_user_path
    expect(response.body).not_to include('id="android-app"')

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANDROID_DOWNLOAD_URL").and_return("https://example.com/lievik.apk")
    get edit_user_path
    expect(response.body).to include('id="android-app"', "https://example.com/lievik.apk")
  end
end
