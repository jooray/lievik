# frozen_string_literal: true

require "rails_helper"

# Background work runs only for users with a trial or paid time, so a user who
# never starts a trial (or never logs in again) costs nothing.
RSpec.describe "Billing-gated jobs" do
  include ActiveJob::TestHelper

  let!(:payer) { User.create!(npub: "npub1payer", pubkey_hex: "c" * 64, display_name: "Payer") }
  let!(:idle) { User.create!(npub: "npub1idle", pubkey_hex: "d" * 64, display_name: "Idle") }
  let!(:payer_source) { payer.sources.create!(source_type: :nostr, identifier: "a" * 64, name: "A") }
  let!(:idle_source) { idle.sources.create!(source_type: :nostr, identifier: "f" * 64, name: "B") }
  let!(:idle_channel) { idle.channels.create!(name: "Idle channel", language: "en", prompt: "anything") }

  before do
    stub_billing
    @billing.grant(payer.npub, "lievik", 20.days.from_now)
    clear_enqueued_jobs
  end

  it "queues ingestion only for users with access, asking billing once per user" do
    RefreshAllSourcesJob.perform_now

    expect(SourceIngestionJob).to have_been_enqueued.with(payer_source.id)
    expect(SourceIngestionJob).not_to have_been_enqueued.with(idle_source.id)
    expect(billing_calls(:entitlement).size).to eq(2)
  end

  it "skips ingestion for a user without access before taking the lock" do
    expect(Ingestion::NostrIngestionService).not_to receive(:new)

    SourceIngestionJob.perform_now(idle_source.id)

    expect(Rails.cache.read(SourceIngestionJob.lock_key(idle_source.id))).to be_nil
    expect(ActivityLog.where(user: idle)).to be_empty
  end

  it "skips rating for a user without access, leaving no log and no follow-up" do
    RateEventsJob.perform_now(idle_channel.id, Array.new(120) { |i| i + 1 })

    expect(RateEventsJob).not_to have_been_enqueued
    expect(ActivityLog.where(user: idle)).to be_empty
  end

  it "never starts a trial" do
    RefreshAllSourcesJob.perform_now
    SourceIngestionJob.perform_now(idle_source.id)

    expect(billing_calls(:start_trial)).to be_empty
  end

  it "keeps a manual event but does not rate it without access" do
    idle.sources.create!(source_type: :manual, identifier: "manual", name: "Manual")

    result = ManualEvents::Creator.new(idle, content: "A note https://example.com").call

    expect(result.event).to be_persisted
    expect(RateEventsJob).not_to have_been_enqueued
    expect(FetchLinksJob).not_to have_been_enqueued
  end
end
