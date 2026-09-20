# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DecisionRatingService do
  let(:user) do
    User.create!(npub: "npub1decision", pubkey_hex: "d" * 64, display_name: "Decider",
                 system_prompt: "You are assisting a Lievik user in curating content.\n\nThe user writes about bitcoin.")
  end
  let(:source) { user.sources.create!(source_type: :manual, identifier: "src", name: "src", distance: 5) }
  let(:event) { source.events.create!(external_id: "evt-1", content: "A note about Lightning payments", event_type: :original, published_at: 1.day.ago) }
  let!(:bitcoin) { user.channels.create!(name: "Bitcoin", language: "en", prompt: "Bitcoin and Lightning content only") }
  let!(:cooking) { user.channels.create!(name: "Cooking", language: "en", prompt: "Recipes") }
  let!(:blank) { user.channels.create!(name: "No criteria", language: "en", prompt: "") }

  let(:client) { instance_double(Ai::DecisionClient, model: "jev-latest") }
  let(:service) { described_class.new(user, client: client) }

  def answer(probabilities, confidence: 0.7)
    { "type" => "score", "probabilities" => probabilities.each_with_index.to_h { |p, i| [ i.to_s, p ] }, "confidence" => confidence }
  end

  before { allow(service).to receive(:sleep) }

  it "rates every channel from one request, with content as state and criteria in the question" do
    captured = nil
    allow(client).to receive(:decide) do |state:, questions:|
      captured = [ state, questions ]
      { "channel_#{bitcoin.id}" => answer([ 0.0, 0.05, 0.25, 0.7 ]), "channel_#{cooking.id}" => answer([ 0.9, 0.1, 0.0, 0.0 ]) }
    end

    results = service.rate_event(event, [ bitcoin, cooking, blank ])

    expect(client).to have_received(:decide).once
    state, questions = captured
    expect(state["content"]).to include("A note about Lightning payments")
    expect(state["author_context"]).to eq("The user writes about bitcoin.") # Lievik preamble stripped
    expect(questions.keys).to contain_exactly("channel_#{bitcoin.id}", "channel_#{cooking.id}")
    expect(questions["channel_#{bitcoin.id}"]["instructions"]).to include("Bitcoin and Lightning content only")
    expect(questions["channel_#{bitcoin.id}"]["criteria"]).to eq(described_class::RUBRIC)

    # expected level 2.65 -> calibrated between the 2.5 (91) and 3.0 (100) knots
    expect(results[bitcoin.id][:score]).to eq(94)
    expect(results[bitcoin.id][:reason]).to eq("Decision model: highly relevant 70%, moderately relevant 25% (confidence 0.7)")
    expect(results[bitcoin.id][:details]).to include("engine" => "decision", "model" => "jev-latest",
                                                      "raw_score" => 2.65, "confidence" => 0.7,
                                                      "calibration" => Ai::Rating::Calibration::VERSION)
    expect(results[bitcoin.id][:details]["probabilities"]).to eq([ 0.0, 0.05, 0.25, 0.7 ])

    expect(results[cooking.id][:score]).to eq(9) # 0.1 -> between 5 and 25
    expect(results[blank.id]).to include(score: 0, reason: "No criteria defined")
  end

  it "renormalises probabilities that do not sum to one" do
    allow(client).to receive(:decide).and_return("channel_#{bitcoin.id}" => answer([ 0.0, 0.0, 1.0, 1.0 ]))

    expect(service.rate_event_for_channel(event, bitcoin)[:details]["raw_score"]).to eq(2.5)
  end

  it "retries a malformed answer and reports an error after MAX_ATTEMPTS" do
    allow(client).to receive(:decide).and_return("channel_#{bitcoin.id}" => { "type" => "score" })

    result = service.rate_event_for_channel(event, bitcoin)

    expect(client).to have_received(:decide).exactly(described_class::MAX_ATTEMPTS).times
    expect(result).to include(score: nil, error: true)
    expect(result[:reason]).to include("no probabilities")
  end

  it "waits for Retry-After on a rate limit and then succeeds" do
    calls = 0
    allow(client).to receive(:decide) do
      calls += 1
      raise Ai::DecisionClient::RateLimited.new("429", retry_after: 7) if calls == 1

      { "channel_#{bitcoin.id}" => answer([ 0.0, 0.0, 0.0, 1.0 ]) }
    end

    result = service.rate_event_for_channel(event, bitcoin)

    expect(service).to have_received(:sleep).with(7)
    expect(result[:score]).to eq(100)
  end

  it "splits more than MAX_QUESTIONS_PER_REQUEST channels across requests" do
    stub_const("#{described_class}::MAX_QUESTIONS_PER_REQUEST", 1)
    allow(client).to receive(:decide) do |questions:, **|
      questions.keys.to_h { |id| [ id, answer([ 1.0, 0.0, 0.0, 0.0 ]) ] }
    end

    results = service.rate_event(event, [ bitcoin, cooking ])

    expect(client).to have_received(:decide).twice
    expect(results.keys).to contain_exactly(bitcoin.id, cooking.id)
  end

  it "returns 'Empty content' without calling the model" do
    allow(Ai::RatingContent).to receive(:prepare).and_return("")
    allow(client).to receive(:decide)

    expect(service.rate_event(event, [ bitcoin ])[bitcoin.id]).to include(score: 0, reason: "Empty content")
    expect(client).not_to have_received(:decide)
  end
end

RSpec.describe Ai::Rating::Calibration do
  it "maps the rubric ends to the scale ends and is monotone" do
    expect(described_class.to_score(0)).to eq(5)
    expect(described_class.to_score(3)).to eq(100)
    expect(described_class.to_score(-1)).to eq(5)
    expect(described_class.to_score(9)).to eq(100)

    scores = (0..300).map { |i| described_class.to_score(i / 100.0) }
    expect(scores).to eq(scores.sort)
  end

  it "passes through the fitted knots" do
    described_class::KNOTS.each { |raw, score| expect(described_class.to_score(raw)).to eq(score) }
  end
end
