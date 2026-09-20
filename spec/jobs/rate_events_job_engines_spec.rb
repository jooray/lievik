# frozen_string_literal: true

require "rails_helper"

# RateEventsJob has two loops: the chat engine rates one channel/event pair per
# call; the decision engine rates one event for the requested channel plus
# every sibling channel that has no rating yet, in one call, adding sibling
# ratings but never overwriting them.
RSpec.describe RateEventsJob do
  let!(:user) { User.create!(npub: "npub1engines", pubkey_hex: "e" * 64, display_name: "Engines") }
  let!(:source) { user.sources.create!(source_type: :manual, identifier: "src", name: "src", distance: 5) }
  let!(:event) { source.events.create!(external_id: "evt-1", content: "Some note", event_type: :original, published_at: 1.day.ago) }
  let!(:primary) { user.channels.create!(name: "Primary", language: "en", prompt: "criteria") }
  let!(:sibling) { user.channels.create!(name: "Sibling", language: "en", prompt: "criteria") }
  let!(:rated) { user.channels.create!(name: "Already rated", language: "en", prompt: "criteria") }
  let!(:no_prompt) { user.channels.create!(name: "No prompt", language: "en", prompt: "") }
  let!(:existing) { ChannelEvent.create!(channel: rated, event: event, relevance_score: 77, relevance_reason: "old") }

  def result(score) = { score: score, reason: "r#{score}", details: { "engine" => "decision" } }

  context "with the decision engine" do
    before do
      user.update!(rating_engine: "decision")
      allow(Ai::DecisionClient).to receive(:configured?).and_return(true)
    end

    it "rates the requested channel and every sibling missing a rating in one call" do
      captured = nil
      service = instance_double(Ai::DecisionRatingService)
      allow(Ai::DecisionRatingService).to receive(:new).and_return(service)
      allow(service).to receive(:rate_event) do |_event, channels|
        captured = channels
        { primary.id => result(80), sibling.id => result(30) }
      end

      described_class.perform_now(primary.id, [ event.id ])

      expect(captured.map(&:id)).to eq([ primary.id, sibling.id ])
      expect(ChannelEvent.find_by(channel: primary, event: event)).to have_attributes(relevance_score: 80, relevance_reason: "r80", rating_details: { "engine" => "decision" })
      expect(ChannelEvent.find_by(channel: sibling, event: event).relevance_score).to eq(30)
      expect(existing.reload.relevance_score).to eq(77)
      expect(ChannelEvent.find_by(channel: no_prompt, event: event)).to be_nil
      expect(user.activity_logs.last).to have_attributes(status: "completed", message: "Rated 1 events for Primary")
    end

    it "does not overwrite a sibling rating that appeared while the request was in flight" do
      service = instance_double(Ai::DecisionRatingService)
      allow(Ai::DecisionRatingService).to receive(:new).and_return(service)
      allow(service).to receive(:rate_event) do |_event, _channels|
        ChannelEvent.create!(channel: sibling, event: event, relevance_score: 55, relevance_reason: "race")
        { primary.id => result(80), sibling.id => result(30) }
      end

      described_class.perform_now(primary.id, [ event.id ])

      expect(ChannelEvent.find_by(channel: sibling, event: event).relevance_score).to eq(55)
      expect(ChannelEvent.find_by(channel: primary, event: event).relevance_score).to eq(80)
    end

    it "leaves the pair unrated when the engine reports an error" do
      service = instance_double(Ai::DecisionRatingService)
      allow(Ai::DecisionRatingService).to receive(:new).and_return(service)
      allow(service).to receive(:rate_event).and_return(primary.id => { score: nil, reason: "Rating failed: 500", error: true }, sibling.id => result(30))

      described_class.perform_now(primary.id, [ event.id ])

      expect(ChannelEvent.find_by(channel: primary, event: event)).to be_nil
      expect(ChannelEvent.find_by(channel: sibling, event: event).relevance_score).to eq(30)
      expect(user.activity_logs.last.message).to eq("Rated 0 events for Primary")
    end

    it "falls back to the chat engine when the decision client is not configured" do
      allow(Ai::DecisionClient).to receive(:configured?).and_return(false)
      allow_any_instance_of(Ai::RatingService).to receive(:rate_event).and_return(score: 42, reason: "chat", details: { "engine" => "chat" })
      expect(Ai::DecisionRatingService).not_to receive(:new)

      described_class.perform_now(primary.id, [ event.id ])

      expect(ChannelEvent.find_by(channel: primary, event: event)).to have_attributes(relevance_score: 42, rating_details: { "engine" => "chat" })
      expect(ChannelEvent.find_by(channel: sibling, event: event)).to be_nil
    end
  end

  context "with the chat engine (default)" do
    it "re-rates an already rated pair instead of failing on the uniqueness validation" do
      ChannelEvent.create!(channel: primary, event: event, relevance_score: 10, relevance_reason: "stale")
      allow_any_instance_of(Ai::RatingService).to receive(:rate_event).and_return(score: 88, reason: "fresh", details: { "engine" => "chat" })

      expect { described_class.perform_now(primary.id, [ event.id ]) }.not_to raise_error

      expect(ChannelEvent.find_by(channel: primary, event: event)).to have_attributes(relevance_score: 88, relevance_reason: "fresh")
      expect(user.activity_logs.last.status).to eq("completed")
    end

    it "rates only the requested channel and records provenance" do
      allow_any_instance_of(Ai::RatingService).to receive(:rate_event).and_return(score: 61, reason: "because", details: { "engine" => "chat", "model" => "m" })
      expect(Ai::DecisionRatingService).not_to receive(:new)

      described_class.perform_now(primary.id, [ event.id ])

      expect(ChannelEvent.find_by(channel: primary, event: event)).to have_attributes(relevance_score: 61, relevance_reason: "because", rating_details: { "engine" => "chat", "model" => "m" })
      expect(ChannelEvent.where(event: event).count).to eq(2) # primary + the pre-existing one
    end
  end
end

RSpec.describe User, "#rating_engine" do
  let(:user) { User.create!(npub: "npub1setting", pubkey_hex: "f" * 64) }

  it "defaults to chat and rejects unknown values" do
    expect(user.rating_engine).to eq("chat")
    user.rating_engine = "bogus"
    expect(user.rating_engine).to eq("chat")
    user.rating_engine = "decision"
    expect(user.rating_engine).to eq("decision")
  end

  it "only reports decision_rating? when the client is configured" do
    user.rating_engine = "decision"
    allow(Ai::DecisionClient).to receive(:configured?).and_return(false)
    expect(user.decision_rating?).to be(false)
    allow(Ai::DecisionClient).to receive(:configured?).and_return(true)
    expect(user.decision_rating?).to be(true)
  end
end
