# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App API billing", type: :request do
  include ActiveJob::TestHelper

  let!(:user) { api_user("payer", "b") }
  let(:token) { api_token_for(user) }
  let!(:source) { user.sources.create!(source_type: :nostr, identifier: "a" * 64, name: "Someone") }
  let!(:channel) { user.channels.create!(name: "Newsletter", language: "en", prompt: "anything") }

  before { clear_enqueued_jobs }

  context "with billing off (self-hosted)" do
    it "gates nothing and hides the billing endpoints" do
      api_post "/api/v1/sources/#{source.id}/refresh", token
      expect(response).to have_http_status(:ok)
      expect(SourceIngestionJob).to have_been_enqueued.with(source.id)

      api_get "/api/v1/billing", token
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("not_found")

      api_get "/api/v1/me", token
      expect(json["billing"]).to include("enabled" => false, "allows" => true)
    end
  end

  context "with billing on" do
    before { stub_billing }

    it "answers 402 paywall for a button when access has ended, without queuing" do
      @billing.grant(user.npub, "lievik", 1.day.ago)

      [ [ "/api/v1/sources/#{source.id}/refresh" ], [ "/api/v1/sources/refresh_all" ], [ "/api/v1/channels/#{channel.id}/rate" ],
       [ "/api/v1/dashboard/rate_all" ], [ "/api/v1/events/rate" ], [ "/api/v1/channels/#{channel.id}/events/rate" ] ].each do |(path)|
        api_post path, token
        expect(response).to have_http_status(:payment_required), path
        expect(json).to include("code" => "paywall", "error" => I18n.t("billing.denied"))
        expect(json["billing_url"]).to eq("http://www.example.com/billing")
      end
      expect(SourceIngestionJob).not_to have_been_enqueued
      expect(RateEventsJob).not_to have_been_enqueued
    end

    it "starts the trial on an explicit refresh, like the web" do
      api_post "/api/v1/sources/#{source.id}/refresh", token

      expect(response).to have_http_status(:ok)
      expect(billing_calls(:start_trial).size).to eq(1)
      expect(SourceIngestionJob).to have_been_enqueued.with(source.id)
    end

    it "keeps a new source when access has ended and says fetching is paused" do
      @billing.grant(user.npub, "lievik", 1.day.ago)

      api_post "/api/v1/sources", token, params: { source: { source_type: "nostr", identifier: "e" * 64, name: "Other" } }

      expect(response).to have_http_status(:created)
      expect(json).to include("notice" => I18n.t("billing.source_saved_paused"), "importing" => false)
    end

    describe "AI requests" do
      it "answers 402 before any stream header and does not call the model" do
        @billing.grant(user.npub, "lievik", 1.day.ago)
        expect(Rag::ChatService).not_to receive(:new)

        api_post "/api/v1/chat/stream", token, params: { question: "What happened?" }

        expect(response).to have_http_status(:payment_required)
        expect(response.media_type).to eq("application/json")
        expect(json["code"]).to eq("paywall")
      end

      it "does not burn the trial on a blank prompt" do
        api_post "/api/v1/channels/ai/stream", token, params: { message: "" }

        expect(response).to have_http_status(:payment_required)
        expect(billing_calls(:start_trial)).to be_empty
      end

      it "answers 429 daily_cap at the cap" do
        @billing.grant(user.npub, "lievik", 20.days.from_now)
        @billing.consume_allowed = false

        api_post "/api/v1/chat/stream", token, params: { question: "What happened?" }

        expect(response).to have_http_status(:too_many_requests)
        expect(json["code"]).to eq("daily_cap")
      end

      it "answers 503 billing_unavailable when billing is down and nothing is cached" do
        @billing.failure = NostrBilling::Unavailable.new("down")

        api_post "/api/v1/chat/stream", token, params: { question: "What happened?" }

        expect(response).to have_http_status(:service_unavailable)
        expect(json["code"]).to eq("billing_unavailable")
      end

      it "saves no content version when generation is denied" do
        @billing.grant(user.npub, "lievik", 1.day.ago)
        content = channel.channel_contents.create!(user: user, title: "Issue 1", content: "old text")

        api_post "/api/v1/channels/#{channel.id}/contents/#{content.id}/generate", token

        expect(response).to have_http_status(:payment_required)
        expect(content.reload.version_history).to be_empty
      end
    end

    describe "the billing endpoints" do
      it "shows status and plans, translated" do
        api_get "/api/v1/billing", token, locale: "sk"

        expect(response).to have_http_status(:ok)
        expect(json.dig("status", "state")).to eq("none")
        expect(json["plans"].map { |p| p["plan"] }).to eq(%w[lievik all-access])
        expect(json["plans"].first).to include("sats" => 15_000, "days" => 30)
        expect(json).to include("min_sats" => 1_000, "max_sats" => 1_000_000, "pending_charges" => [])
      end

      it "starts the trial" do
        api_post "/api/v1/billing/trial", token

        expect(json.dig("status", "state")).to eq("trial")
        expect(json["notice"]).to include(Billing.status(user).until_time.year.to_s)
        expect(RefreshAllSourcesJob).to have_been_enqueued.with(user.id)
      end

      it "creates a charge, lists it, and reports the payment once" do
        api_post "/api/v1/billing/charges", token, params: { plan: "all-access" }
        expect(json).to eq("invoice_id" => "inv_1", "checkout_url" => "https://pay.example.test/i/inv_1")
        expect(billing_calls(:create_charge).last[1..]).to eq([ user.npub, "all-access", nil, "http://www.example.com/billing/app_return" ])

        api_get "/api/v1/billing", token
        expect(json["pending_charges"]).to eq([ { "invoice_id" => "inv_1", "plan" => "all-access", "checkout_url" => "https://pay.example.test/i/inv_1" } ])

        api_get "/api/v1/billing/charges/inv_1", token
        expect(json["settled"]).to be(false)

        @billing.settle!("inv_1")
        api_get "/api/v1/billing/charges/inv_1", token
        expect(json["settled"]).to be(true)
        expect(json.dig("status", "state")).to eq("active")
        expect(json["notice"]).to start_with("Paid.")
        expect(RefreshAllSourcesJob).to have_been_enqueued.with(user.id)

        api_get "/api/v1/billing/charges/inv_1", token
        expect(response).to have_http_status(:not_found)
      end

      it "settles a paid charge when the billing page is opened" do
        api_post "/api/v1/billing/charges", token, params: { plan: "lievik" }
        @billing.settle!(json["invoice_id"])

        api_get "/api/v1/billing", token
        expect(json["notice"]).to start_with("Paid.")
        expect(json["pending_charges"]).to be_empty
      end

      it "rejects bad input without calling billing" do
        api_post "/api/v1/billing/charges", token, params: { plan: "emanator-ai" }
        expect(response).to have_http_status(:unprocessable_content)
        api_post "/api/v1/billing/charges", token, params: { plan: "lievik", sats: 10 }
        expect(json["error"]).to eq(I18n.t("billing.errors.sats_range", min: 1_000, max: 1_000_000))

        expect(billing_calls(:create_charge)).to be_empty
      end
    end
  end
end
