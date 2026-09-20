# frozen_string_literal: true

require "rails_helper"

RSpec.describe "bunker:// login", type: :request do
  let(:signer) { "b" * 64 }
  let(:uri) { "bunker://#{signer}?relay=wss%3A%2F%2Fnos.lol&secret=s3cr3t" }

  before { allow(Nip46SupervisorJob).to receive(:ensure_running) }

  it "creates a pinned bunker session and binds it to the browser" do
    post auth_nostr_bunker_path, params: { bunker_uri: uri }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["ok"]).to be(true)

    record = NostrAuthSession.order(:id).last
    expect(record.flow).to eq("bunker")
    expect(record.signer_pubkey).to eq(signer)
    expect(record.secret).to eq("s3cr3t")
    expect(session[:nostr_connect_session_id]).to eq(record.session_id)
  end

  it "starts the supervisor so the connect actually goes out" do
    expect(Nip46SupervisorJob).to receive(:ensure_running)

    post auth_nostr_bunker_path, params: { bunker_uri: uri }
  end

  # The signer's relays are honoured, but our known-good auth relays are added
  # so a signer advertising one dead relay is not unreachable.
  it "unions the advertised relays with the app's own" do
    post auth_nostr_bunker_path, params: { bunker_uri: uri }

    relays = NostrAuthSession.order(:id).last.relay_urls
    expect(relays).to include("wss://nos.lol")
    expect(relays.size).to be > 1
  end

  it "accepts a bunker URI with no secret" do
    post auth_nostr_bunker_path, params: { bunker_uri: "bunker://#{signer}?relay=wss://nos.lol" }

    expect(response).to have_http_status(:ok)
    expect(NostrAuthSession.order(:id).last.secret).to eq("")
  end

  it "rejects a malformed URI without creating a session" do
    expect {
      post auth_nostr_bunker_path, params: { bunker_uri: "bunker://nope" }
    }.not_to change(NostrAuthSession, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["ok"]).to be(false)
    expect(response.parsed_body["error"]).to include("bunker://")
  end

  it "rejects a URI with no relay" do
    post auth_nostr_bunker_path, params: { bunker_uri: "bunker://#{signer}" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  # A relay URL is an outbound destination chosen by whoever pasted the link.
  it "filters out non-public relay destinations" do
    post auth_nostr_bunker_path,
         params: { bunker_uri: "bunker://#{signer}?relay=ws%3A%2F%2F127.0.0.1&relay=ws%3A%2F%2F169.254.169.254" }

    if response.ok?
      expect(NostrAuthSession.order(:id).last.relay_urls)
        .to all(satisfy { |r| !r.include?("127.0.0.1") && !r.include?("169.254") })
    else
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "replaces this browser's previous pending session" do
    post auth_nostr_bunker_path, params: { bunker_uri: uri }
    first = NostrAuthSession.order(:id).last

    post auth_nostr_bunker_path, params: { bunker_uri: uri }

    expect(first.reload.consumed_at).to be_present
    expect(session[:nostr_connect_session_id]).not_to eq(first.session_id)
  end
end
