# frozen_string_literal: true

require "rails_helper"

# CSP is the defence-in-depth layer behind output escaping (SEC-M5), but it only
# helps if the app actually stays compliant with it. Under
# `script-src 'self'`, an inline `onclick=`/`oninput=` handler silently does
# nothing and an un-nonced inline <script>/<style> silently fails to apply —
# neither raises, so a render spec would still pass while the page is broken.
#
# This walks the rendered HTML of every primary page and fails on either.
RSpec.describe "Content Security Policy compliance", type: :request do
  INLINE_HANDLER = /\son(?:click|change|input|submit|load|error|focus|blur|keyup|keydown)\s*=/i
  OPENING_SCRIPT_OR_STYLE = /<(script|style)(\s[^>]*)?>/i

  def expect_csp_compliant_body
    expect(response).to have_http_status(:ok)

    handlers = response.body.scan(INLINE_HANDLER)
    expect(handlers).to be_empty,
      "found #{handlers.size} inline event handler(s); CSP `script-src 'self'` will not run them. " \
      "Use a Stimulus data-action instead."

    response.body.scan(OPENING_SCRIPT_OR_STYLE) do
      tag = Regexp.last_match(0)
      # External assets are covered by 'self'; only inline blocks need a nonce.
      next if tag.match?(/\bsrc\s*=/i)

      expect(tag).to match(/\bnonce\s*=/i),
        "inline <#{Regexp.last_match(1)}> without a nonce will be blocked by CSP: #{tag}"
    end
  end

  describe "the policy itself" do
    it "is enforced (not report-only) and does not allow unsafe-inline scripts" do
      get nostr_login_path

      policy = response.headers["Content-Security-Policy"]
      expect(policy).to be_present
      expect(response.headers["Content-Security-Policy-Report-Only"]).to be_nil

      script_src = policy[/script-src ([^;]*)/, 1]
      expect(script_src).to include("'self'")
      expect(script_src).not_to include("unsafe-inline")
      expect(script_src).not_to include("unsafe-eval")
      expect(script_src).to match(/'nonce-/)

      expect(policy).to include("object-src 'none'")
      expect(policy).to include("frame-ancestors 'none'")
    end
  end

  describe "unauthenticated pages" do
    it "renders the landing page CSP-clean" do
      get root_path
      expect_csp_compliant_body
    end

    it "renders the login page CSP-clean" do
      get nostr_login_path
      expect_csp_compliant_body
    end
  end

  describe "authenticated pages" do
    let!(:user) do
      User.create!(npub: "npub1cspowner", pubkey_hex: "c" * 64, display_name: "CSP Owner")
    end

    let!(:source) do
      user.sources.create!(source_type: :manual, identifier: "csp-src", name: "CSP Source", distance: 5)
    end

    let!(:event) do
      source.events.create!(
        external_id: "csp-evt",
        content: "A note about bitcoin",
        event_type: :original,
        published_at: 1.day.ago
      )
    end

    let!(:channel) do
      user.channels.create!(name: "CSP Channel", language: "en", prompt: "anything")
    end

    let!(:channel_event) do
      ChannelEvent.create!(channel: channel, event: event, relevance_score: 80)
    end

    before do
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    end

    {
      "dashboard" => -> { dashboard_path },
      "sources index" => -> { sources_path },
      "source show" => -> { source_path(Source.last) },
      "source edit" => -> { edit_source_path(Source.last) },
      "channels index" => -> { channels_path },
      "channel show" => -> { channel_path(Channel.last) },
      "channel settings" => -> { settings_channel_path(Channel.last) },
      "events index" => -> { events_path },
      "event show" => -> { event_path(Event.last) },
      "activity logs" => -> { activity_logs_path },
      "user settings" => -> { edit_user_path }
    }.each do |label, path|
      it "renders #{label} CSP-clean" do
        get instance_exec(&path)
        expect_csp_compliant_body
      end
    end
  end
end
