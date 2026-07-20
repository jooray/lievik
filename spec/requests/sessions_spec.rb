# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nostr sessions", type: :request do
  before do
    allow(Nip46SupervisorJob).to receive(:perform_later)
    Rails.cache.clear
  end

  it "does not accept a callback pubkey or method from query parameters" do
    get auth_nostr_callback_path, params: { pubkey: "a" * 64, method: "nip46" }

    expect(response).to redirect_to(nostr_login_path)
  end

  it "completes the Rails-session-bound NIP-46 session and ignores tampered callback params" do
    get nostr_login_path
    bound = NostrAuthSession.order(:created_at).last
    bound.update!(authenticated_pubkey: "c" * 64, authenticated_user_pubkey: "d" * 64)
    other = NostrAuthSession.create!(bound.attributes.except("id", "session_id", "created_at", "updated_at").merge(
      session_id: SecureRandom.uuid,
      temp_pubkey: "b" * 64,
      authenticated_user_pubkey: "e" * 64
    ))
    user = User.create!(npub: "npub1bound", pubkey_hex: "d" * 64, display_name: "bound user")
    allow_any_instance_of(Nostr::AuthService).to receive(:find_or_create_user).with("d" * 64).and_return(user)

    get auth_nostr_callback_path, params: { pubkey: other.authenticated_user_pubkey, method: "nip07" }

    expect(response).to redirect_to(dashboard_path)
    expect(bound.reload.consumed_at).to be_present
    expect(NostrAuthSession.active.exists?(bound.id)).to be(false)
    expect(NostrAuthSession.exists?(other.id)).to be(true)

    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "refuses to create sessions and start the supervisor when active authentication is at capacity" do
    stub_const("SessionsController::MAX_ACTIVE_AUTH_SESSIONS", 0)

    expect { get nostr_login_path }.not_to change(NostrAuthSession, :count)

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include("Login is busy right now")
    expect(Nip46SupervisorJob).not_to have_received(:perform_later)
  end

  it "keeps the browser's existing session when replacement admission is rejected" do
    get nostr_login_path
    existing = NostrAuthSession.order(:created_at).last
    allow(Rails.cache).to receive(:write).with(
      "nostr-auth-session-admission",
      kind_of(String),
      expires_in: 10.seconds,
      unless_exist: true
    ).and_return(false)

    expect { get nostr_login_path }.not_to change(NostrAuthSession, :count)

    expect(response).to have_http_status(:service_unavailable)
    expect(NostrAuthSession.exists?(existing.id)).to be(true)
  end

  it "caps concurrent pending logins independently of worker concurrency" do
    # The multiplexed supervisor serves every pending login from one connection,
    # so the cap is a plain memory / relay fan-out guard, not a worker count.
    expect(SessionsController::MAX_ACTIVE_AUTH_SESSIONS).to be > 0
    expect(SessionsController::MAX_ACTIVE_AUTH_SESSIONS).to eq(50) unless ENV.key?("MAX_ACTIVE_NOSTR_AUTH_SESSIONS")
  end

  it "allows the same browser to replace its pending session at capacity" do
    stub_const("SessionsController::MAX_ACTIVE_AUTH_SESSIONS", 1)
    get nostr_login_path
    existing = NostrAuthSession.order(:created_at).last

    expect { get nostr_login_path }.to change(NostrAuthSession, :count).by(1)

    replacement = NostrAuthSession.order(:created_at).last
    expect(response).to have_http_status(:ok)
    expect(replacement.id).not_to eq(existing.id)
    expect(existing.reload.consumed_at).to be_present
    expect(NostrAuthSession.active.where(authenticated_pubkey: nil).count).to eq(1)
    expect(Nip46SupervisorJob).to have_received(:perform_later).twice
  end

  it "keeps the existing browser session when replacement supervisor enqueue fails" do
    get nostr_login_path
    existing = NostrAuthSession.order(:created_at).last
    allow(Nip46SupervisorJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError)

    expect { get nostr_login_path }.to raise_error(ActiveJob::EnqueueError)

    expect(NostrAuthSession.exists?(existing.id)).to be(true)
    expect(NostrAuthSession.count).to eq(1)
  end

  describe "GET /auth/nostr/poll" do
    it "reports expired when there is no pending session in the Rails session" do
      get auth_nostr_poll_path

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["authenticated"]).to be(false)
      expect(body["expired"]).to be(true)
    end

    it "keeps polling while the auth session is still active" do
      get nostr_login_path

      get auth_nostr_poll_path

      body = JSON.parse(response.body)
      expect(body["authenticated"]).to be(false)
      expect(body["expired"]).to be_nil
    end

    it "reports expired once the auth session leaves the active scope" do
      get nostr_login_path
      NostrAuthSession.order(:created_at).last.consume!

      get auth_nostr_poll_path

      body = JSON.parse(response.body)
      expect(body["authenticated"]).to be(false)
      expect(body["expired"]).to be(true)
    end

    it "returns the callback redirect once the session is authenticated" do
      get nostr_login_path
      NostrAuthSession.order(:created_at).last.update!(
        authenticated_pubkey: "c" * 64,
        authenticated_user_pubkey: "d" * 64
      )

      get auth_nostr_poll_path

      body = JSON.parse(response.body)
      expect(body["authenticated"]).to be(true)
      expect(body["redirect_url"]).to eq(auth_nostr_callback_path)
    end
  end
end
