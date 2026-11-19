# frozen_string_literal: true

class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: :landing

  # The landing page shows live posts of the Lievik Nostr account through the
  # vendored nostr-live widget, which reads them from these relays over
  # WebSocket. Allowed on this page only; the rest of the app stays on 'self'.
  content_security_policy only: :landing do |policy|
    policy.connect_src :self, "wss://nostr.cypherpunk.today", "wss://relay.primal.net"
  end

  # Public landing page at "/". Signed-in users go straight to their dashboard;
  # everyone else sees the marketing page with a "Launch app" link into auth.
  def landing
    return redirect_to dashboard_path if user_signed_in?

    render layout: false
  end
end
