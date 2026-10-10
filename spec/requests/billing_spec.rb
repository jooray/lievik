# frozen_string_literal: true

require "rails_helper"

# Paid access on the hosted instance: what is gated, when the one-time trial
# starts, what a denial looks like, and that a self-hosted install (billing
# off) sees none of it.
RSpec.describe "Billing", type: :request do
  include ActiveJob::TestHelper

  let!(:user) { User.create!(npub: "npub1billing", pubkey_hex: "b" * 64, display_name: "Payer") }
  let!(:source) { user.sources.create!(source_type: :nostr, identifier: "a" * 64, name: "Someone") }
  let!(:channel) { user.channels.create!(name: "Newsletter", language: "en", prompt: "anything") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    clear_enqueued_jobs
  end

  context "with billing off (self-hosted)" do
    it "queues work and shows no billing UI" do
      post refresh_source_path(source)
      expect(SourceIngestionJob).to have_been_enqueued.with(source.id)

      get dashboard_path
      expect(response.body).not_to include("billing-status")

      get billing_path
      expect(response).to have_http_status(:not_found)
    end
  end

  context "with billing on" do
    before { stub_billing }

    it "starts the trial on an explicit refresh and catches up on the paused work" do
      post refresh_source_path(source)

      expect(billing_calls(:start_trial).size).to eq(1)
      expect(SourceIngestionJob).to have_been_enqueued.with(source.id)
      expect(RefreshAllSourcesJob).to have_been_enqueued.with(user.id)
      expect(RateEventsJob).to have_been_enqueued.with(channel.id)
    end

    it "sends a user whose access ended to the billing page instead of queuing" do
      @billing.grant(user.npub, "lievik", 1.day.ago)

      post refresh_source_path(source)

      expect(response).to redirect_to(billing_path)
      expect(SourceIngestionJob).not_to have_been_enqueued
      expect(billing_calls(:start_trial)).to be_empty
    end

    it "gates every rate button" do
      @billing.grant(user.npub, "lievik", 1.day.ago)

      post rate_all_path
      expect(response).to redirect_to(billing_path)
      post rate_channel_path(channel)
      expect(response).to redirect_to(billing_path)
      expect(RateEventsJob).not_to have_been_enqueued
    end

    it "keeps a new source when access has ended, and says fetching is paused" do
      @billing.grant(user.npub, "lievik", 1.day.ago)

      expect {
        post sources_path, params: { source: { source_type: "nostr", identifier: "e" * 64, name: "Other" } }
      }.to change(user.sources, :count).by(1)
      expect(flash[:notice]).to eq(I18n.t("billing.source_saved_paused"))
      expect(SourceIngestionJob).not_to have_been_enqueued
    end

    it "lets a paying user through without a trial" do
      @billing.grant(user.npub, "all-access", 20.days.from_now)

      post refresh_source_path(source)

      expect(SourceIngestionJob).to have_been_enqueued.with(source.id)
      expect(billing_calls(:start_trial)).to be_empty
    end

    describe "AI requests" do
      it "answers 402 before any stream header, and does not call the model" do
        @billing.grant(user.npub, "lievik", 1.day.ago)
        expect(Rag::ChatService).not_to receive(:new)

        post rag_chat_ask_stream_path, params: { question: "What happened?" }, as: :json

        expect(response).to have_http_status(:payment_required)
        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body).to include("code" => "paywall", "billing_url" => billing_path)
      end

      it "does not burn the trial on a blank prompt" do
        post channel_ai_chat_stream_path, params: { message: "" }, as: :json

        expect(response).to have_http_status(:payment_required)
        expect(billing_calls(:start_trial)).to be_empty
      end

      it "starts the trial on the first real question and counts it" do
        allow_any_instance_of(Rag::ChatService).to receive(:chat).and_return(success: true, answer: "ok", cited_events: [], context_event_ids: [])

        post rag_chat_ask_path, params: { question: "What happened?" }, as: :json

        expect(response).to have_http_status(:ok)
        expect(billing_calls(:start_trial).size).to eq(1)
        expect(billing_calls(:consume).last[3]).to eq("chat")
      end

      it "answers 429 at the daily cap" do
        @billing.grant(user.npub, "lievik", 20.days.from_now)
        @billing.consume_allowed = false

        post rag_chat_ask_path, params: { question: "What happened?" }, as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body["code"]).to eq("daily_cap")
      end

      it "answers 503 when billing is down and nothing is cached" do
        @billing.failure = NostrBilling::Unavailable.new("down")

        post rag_chat_ask_path, params: { question: "What happened?" }, as: :json

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["code"]).to eq("billing_unavailable")
      end

      it "saves no content version when generation is denied" do
        @billing.grant(user.npub, "lievik", 1.day.ago)
        content = channel.channel_contents.create!(user: user, title: "Issue 1", content: "old text")

        post generate_stream_channel_content_path(channel, content)

        expect(response).to have_http_status(:payment_required)
        expect(content.reload.content).to eq("old text")
      end
    end

    describe "the billing page" do
      it "shows the state, both plans and a trial button" do
        get billing_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-billing-state="none"')
        expect(response.body).to include('data-plan="lievik"', 'data-plan="all-access"')
        expect(response.body).to include(billing_trial_path)
      end

      it "starts the trial from the button" do
        post billing_trial_path

        expect(response).to redirect_to(dashboard_path)
        expect(flash[:notice]).to include(Billing.status(user).until_time.year.to_s)
        expect(RefreshAllSourcesJob).to have_been_enqueued.with(user.id)
      end

      it "sends the payer straight to BTCPay and reports the payment once on return" do
        post billing_charges_path, params: { plan: "all-access" }
        expect(response).to redirect_to("https://pay.example.test/i/inv_1")
        expect(billing_calls(:create_charge).last[1..]).to eq([ user.npub, "all-access", nil, billing_url ])

        @billing.settle!("inv_1")
        get billing_path
        expect(response.body).to include('data-billing-state="active"')
        expect(flash[:notice]).to start_with("Paid.")
        expect(RefreshAllSourcesJob).to have_been_enqueued.with(user.id)

        get billing_path
        expect(flash[:notice]).to be_nil
      end

      it "lets only its own forms redirect to https" do
        get billing_path
        expect(response.headers["Content-Security-Policy"]).to include("form-action 'self' https:")

        get dashboard_path
        expect(response.headers["Content-Security-Policy"]).not_to include("form-action 'self' https:")
      end

      it "rejects bad input without calling billing" do
        post billing_charges_path, params: { plan: "emanator-ai" }
        post billing_charges_path, params: { plan: "lievik", sats: "10" }

        expect(billing_calls(:create_charge)).to be_empty
      end
    end

    describe "the status banner" do
      it "offers the trial to a new user" do
        get billing_status_path
        expect(response.body).to include('data-billing-banner="none"', billing_trial_path)
      end

      it "is silent for a paying user" do
        @billing.grant(user.npub, "lievik", 20.days.from_now)
        get billing_status_path
        expect(response.body).not_to include("data-billing-banner")
      end

      it "is loaded lazily by every page but the billing page" do
        get dashboard_path
        expect(response.body).to include(%(id="billing-status" src="#{billing_status_path}"))
      end
    end

    it "renders in every language" do
      %w[sk cs es].each do |locale|
        user.update!(locale: locale)
        get billing_path
        expect(response).to have_http_status(:ok)
        get billing_status_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
