# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rating engine setting", type: :request do
  let!(:user) { User.create!(npub: "npub1ratingui", pubkey_hex: "c" * 64, display_name: "UI") }

  before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

  it "saves the engine from the settings form" do
    patch user_path, params: { user: { rating_engine: "decision" } }

    expect(response).to redirect_to(edit_user_path)
    expect(user.reload.rating_engine).to eq("decision")
  end

  it "shows the decision option disabled when the client is not configured" do
    allow(Ai::DecisionClient).to receive(:configured?).and_return(false)

    get edit_user_path

    expect(response.body).to include("Rating Engine")
    decision_input = response.body[/<input[^>]*value="decision"[^>]*>/]
    expect(decision_input).to include("disabled")
    expect(response.body).to include("Not configured")
  end

  it "shows the decision option enabled when configured" do
    allow(Ai::DecisionClient).to receive(:configured?).and_return(true)
    allow(Ai::DecisionClient).to receive(:model).and_return("jev-latest")

    get edit_user_path

    decision_input = response.body[/<input[^>]*value="decision"[^>]*>/]
    expect(decision_input).not_to include("disabled")
    expect(response.body).to include("jev-latest")
  end
end
