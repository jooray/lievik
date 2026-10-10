# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP tools that queue paid work" do
  include ActiveJob::TestHelper

  let!(:user) { User.create!(npub: "npub1agent", pubkey_hex: "9" * 64, display_name: "Agent") }
  let!(:channel) { user.channels.create!(name: "Feed", language: "en", prompt: "anything") }
  let!(:source) { user.sources.create!(source_type: :nostr, identifier: "8" * 64, name: "S") }

  before { clear_enqueued_jobs }

  it "work as before with billing off" do
    Mcp::Tools::RateChannel.new(user, { channel_id: channel.id }).call
    expect(RateEventsJob).to have_been_enqueued.with(channel.id)
  end

  context "with billing on" do
    before { stub_billing }

    it "start the trial like the buttons do" do
      Mcp::Tools::RefreshSource.new(user, { source_id: source.id }).call

      expect(billing_calls(:start_trial).size).to eq(1)
      expect(SourceIngestionJob).to have_been_enqueued.with(source.id)
    end

    it "refuse with PaymentRequired once access has ended" do
      @billing.grant(user.npub, "lievik", 1.day.ago)

      expect { Mcp::Tools::RateChannel.new(user, { channel_id: channel.id }).call }
        .to raise_error(Mcp::Tools::Base::PaymentRequired)
      expect(RateEventsJob).not_to have_been_enqueued
    end
  end
end
