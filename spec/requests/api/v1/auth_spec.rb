# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App API auth", type: :request do
  let(:keypair) { Nostr::Keygen.new.generate_key_pair }
  let(:host) { "www.example.com" }

  before do
    use_memory_cache
    allow(Nip46SupervisorJob).to receive(:perform_later)
    allow(RefreshUserProfileJob).to receive(:perform_later)
  end

  def signed_event(challenge, domain: host, content: "", created_at: Time.current.to_i, kind: 22242)
    tags = [ [ "challenge", challenge ] ]
    tags << [ "domain", domain ] if domain
    Nostr::Event.new(pubkey: keypair.public_key.to_s, created_at: created_at, kind: kind, tags: tags, content: content)
      .sign(keypair.private_key).to_h
  end

  def http_auth_event(challenge, url: "http://#{host}/api/v1/auth/token", method: "POST", created_at: Time.current.to_i)
    tags = [ [ "u", url ], [ "method", method ], [ "challenge", challenge ] ]
    Nostr::Event.new(pubkey: keypair.public_key.to_s, created_at: created_at, kind: 27235, tags: tags, content: "")
      .sign(keypair.private_key).to_h
  end

  def new_challenge
    post "/api/v1/auth/challenge", as: :json
    expect(response).to have_http_status(:ok)
    json["challenge"]
  end

  describe "NIP-98 proof (kind 27235)" do
    it "names the token endpoint in the challenge and issues a token for a matching proof" do
      post "/api/v1/auth/challenge", as: :json
      expect(json["token_url"]).to eq("http://#{host}/api/v1/auth/token")

      post "/api/v1/auth/token", params: { signed_event: http_auth_event(json["challenge"], url: "https://#{host}/api/v1/auth/token"), device_name: "Fold" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json["token"]).to start_with("lvk_")
      expect(ApiToken.last.name).to eq("App: Fold")
    end

    it "refuses a proof for another endpoint, method, or without our challenge" do
      [
        http_auth_event(new_challenge, url: "https://evil.example/api/v1/auth/token"),
        http_auth_event(new_challenge, url: "https://#{host}/api/v1/me"),
        http_auth_event(new_challenge, method: "GET"),
        http_auth_event(SecureRandom.hex(32))
      ].each do |event|
        post "/api/v1/auth/token", params: { signed_event: event }, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(json["code"]).to eq("auth_failed")
      end
    end

    it "is single-use" do
      event = http_auth_event(new_challenge)
      post "/api/v1/auth/token", params: { signed_event: event }, as: :json
      expect(response).to have_http_status(:ok)
      post "/api/v1/auth/token", params: { signed_event: event }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "signed challenge" do
    it "issues a device token for a Schnorr-signed kind 22242 event" do
      post "/api/v1/auth/challenge", as: :json
      expect(json).to include("domain" => host, "expires_in" => 300)
      expect(json["challenge"]).to match(/\A[0-9a-f]{64}\z/)

      expect {
        post "/api/v1/auth/token", params: { signed_event: signed_event(json["challenge"]), device_name: "Pixel 9" }, as: :json
      }.to change(User, :count).by(1).and change(ApiToken, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json["token"]).to start_with("lvk_")
      expect(json.dig("user", "pubkey_hex")).to eq(keypair.public_key.to_s)
      user = User.find_by!(pubkey_hex: keypair.public_key.to_s)
      expect(user.api_tokens.last.name).to eq("App: Pixel 9")
      expect(user.sources.manual.count).to eq(1)

      get "/api/v1/me", headers: api_headers(json["token"])
      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "npub")).to eq(user.npub)
    end

    it "accepts a signed event sent as a JSON string" do
      challenge = new_challenge
      post "/api/v1/auth/token", params: { signed_event: signed_event(challenge).to_json, device_name: "Pixel" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "is single-use" do
      challenge = new_challenge
      event = signed_event(challenge)
      post "/api/v1/auth/token", params: { signed_event: event, device_name: "A" }, as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/auth/token", params: { signed_event: event, device_name: "B" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("auth_failed")
    end

    it "rejects a challenge the server never issued" do
      post "/api/v1/auth/token", params: { signed_event: signed_event(SecureRandom.hex(32)) }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("auth_failed")
    end

    it "rejects an expired challenge" do
      challenge = new_challenge
      travel 6.minutes do
        post "/api/v1/auth/token", params: { signed_event: signed_event(challenge) }, as: :json
      end
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a proof for another domain, without a domain, or with a bad signature" do
      [ signed_event(new_challenge, domain: "evil.example"),
       signed_event(new_challenge, domain: nil),
       signed_event(new_challenge).merge("content" => "tampered") ].each do |event|
        post "/api/v1/auth/token", params: { signed_event: event }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
      expect(ApiToken.count).to eq(0)
    end

    it "burns the challenge even when the proof fails" do
      challenge = new_challenge
      post "/api/v1/auth/token", params: { signed_event: signed_event(challenge, domain: "evil.example") }, as: :json
      post "/api/v1/auth/token", params: { signed_event: signed_event(challenge) }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/session" do
    it "revokes only the token used for the request" do
      user = api_user
      token = api_token_for(user, name: "App: phone")
      other = api_token_for(user, name: "laptop")

      delete "/api/v1/session", headers: api_headers(token)
      expect(response).to have_http_status(:no_content)

      get "/api/v1/me", headers: api_headers(token)
      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("unauthorized")
      get "/api/v1/me", headers: api_headers(other)
      expect(response).to have_http_status(:ok)
    end
  end

  it "answers 401 without a token, with an unknown one, and with an expired one" do
    user = api_user
    expired = ApiToken.generate(user, name: "old", expires_at: 1.minute.ago).plain_token

    [ nil, "lvk_nope", expired ].each do |token|
      get "/api/v1/me", headers: token ? api_headers(token) : {}
      expect(response).to have_http_status(:unauthorized)
      expect(json).to include("code" => "unauthorized")
    end
  end

  describe "NIP-46" do
    it "starts a nostrconnect session with a secret poll token" do
      post "/api/v1/auth/nostrconnect", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["uri"]).to start_with("nostrconnect://")
      expect(json["poll_token"]).to match(/\A[0-9a-f]{64}\z/)
      auth_session = NostrAuthSession.find_by!(session_id: json["session_id"])
      expect(auth_session.poll_token_digest).to eq(ApiToken.digest_for(json["poll_token"]))
      expect(Nip46SupervisorJob).to have_received(:perform_later)
    end

    it "answers busy at capacity, like the web" do
      stub_const("Nostr::LoginAdmission::MAX_ACTIVE_AUTH_SESSIONS", 0)

      expect { post "/api/v1/auth/nostrconnect", as: :json }.not_to change(NostrAuthSession, :count)
      expect(response).to have_http_status(:service_unavailable)
      expect(json["code"]).to eq("busy")
    end

    it "polls pending, then issues the token exactly once" do
      post "/api/v1/auth/nostrconnect", as: :json
      session_id = json["session_id"]
      poll_token = json["poll_token"]

      post "/api/v1/auth/poll", params: { session_id: session_id, poll_token: poll_token }, as: :json
      expect(json).to eq("status" => "pending", "auth_url" => nil)

      post "/api/v1/auth/poll", params: { session_id: session_id, poll_token: "0" * 64 }, as: :json
      expect(response).to have_http_status(:not_found)

      pubkey = keypair.public_key.to_s
      NostrAuthSession.find_by!(session_id: session_id).update!(authenticated_pubkey: "c" * 64, authenticated_user_pubkey: pubkey)

      post "/api/v1/auth/poll", params: { session_id: session_id, poll_token: "0" * 64 }, as: :json
      expect(response).to have_http_status(:not_found)

      post "/api/v1/auth/poll", params: { session_id: session_id, poll_token: poll_token, device_name: "Pixel" }, as: :json
      expect(json["status"]).to eq("authenticated")
      expect(json["token"]).to start_with("lvk_")
      expect(json.dig("user", "pubkey_hex")).to eq(pubkey)
      expect(ApiToken.last.name).to eq("App: Pixel")
      expect(NostrAuthSession.find_by!(session_id: session_id).consumed_at).to be_present

      post "/api/v1/auth/poll", params: { session_id: session_id, poll_token: poll_token }, as: :json
      expect(json).to eq("status" => "expired")
      expect(ApiToken.count).to eq(1)
    end

    it "reports expired once the approval window has passed" do
      post "/api/v1/auth/nostrconnect", as: :json
      NostrAuthSession.find_by!(session_id: json["session_id"]).update!(expires_at: 1.minute.ago)

      post "/api/v1/auth/poll", params: { session_id: json["session_id"], poll_token: json["poll_token"] }, as: :json
      expect(json).to eq("status" => "expired")
    end

    it "rejects an unusable bunker link" do
      post "/api/v1/auth/bunker", params: { bunker_uri: "https://example.com" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("invalid_link")
    end

    it "starts a bunker session with a poll token" do
      signer = Nostr::Keygen.new.generate_key_pair.public_key.to_s
      post "/api/v1/auth/bunker", params: { bunker_uri: "bunker://#{signer}?relay=wss://nos.lol" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("session_id", "poll_token", "expires_at")
      expect(json).not_to have_key("uri")
      expect(NostrAuthSession.find_by!(session_id: json["session_id"])).to be_bunker
    end
  end
end
