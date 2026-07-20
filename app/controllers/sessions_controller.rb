# frozen_string_literal: true

class SessionsController < ApplicationController
  # One multiplexed supervisor (Nostr::Nip46Supervisor) serves every pending login
  # at once with O(1) DB/WebSocket connections, so admission is no longer bound to
  # one worker per login. The cap just guards memory / relay subscription fan-out.
  MAX_ACTIVE_AUTH_SESSIONS = ENV.fetch("MAX_ACTIVE_NOSTR_AUTH_SESSIONS", 50).to_i

  skip_before_action :authenticate_user!
  rate_limit to: 5, within: 1.minute, only: :new, name: "nostr-login-ip", with: :rate_limit_exceeded
  rate_limit to: 60, within: 1.minute, only: :new, name: "nostr-login-global", by: -> { "global" }, with: :rate_limit_exceeded

  def new
    # Cancel this browser's previous pending login so its listener bails promptly
    # instead of holding a worker + capacity slot until the approval window ends.
    consume_pending_sessions!

    # Serialize session creation so a burst can't slip past the capacity check.
    admission_token = SecureRandom.hex(16)
    admitted = Rails.cache.write("nostr-auth-session-admission", admission_token, expires_in: 10.seconds, unless_exist: true)
    unless admitted
      render_unavailable(:service_unavailable, "Login is busy right now",
                        "Too many people are signing in at once. Give it a few seconds and try again.")
      return
    end

    begin
      NostrAuthSession.cleanup_expired!
      if NostrAuthSession.active.where(authenticated_pubkey: nil).count >= MAX_ACTIVE_AUTH_SESSIONS
        render_unavailable(:service_unavailable, "Login is busy right now",
                          "Too many people are signing in at once. Give it a few seconds and try again.")
        return
      end

      session[:nostr_nip07_challenge] = SecureRandom.hex(32)
      @connect_data = Nostr::AuthService.new.generate_connect_uri
      session[:nostr_connect_session_id] = @connect_data[:session_id]

      # Ensure the multiplexed listener is running — it will pick up this session
      # from the DB within ~1s. Polls just check the DB for the persisted result.
      Nip46SupervisorJob.ensure_running
    rescue StandardError
      NostrAuthSession.find_by(session_id: @connect_data&.dig(:session_id))&.destroy!
      raise
    ensure
      Rails.cache.delete("nostr-auth-session-admission") if Rails.cache.read("nostr-auth-session-admission") == admission_token
    end

    # Generate QR code
    @qr_code = RQRCode::QRCode.new(@connect_data[:uri])
  end

  def poll
    session_id = session[:nostr_connect_session_id]

    if session_id.blank?
      render json: { authenticated: false, expired: true, error: "No pending session" }
      return
    end

    # DB-only check — background job handles the relay subscription
    result = Nostr::AuthService.new.check_session(session_id)

    if result && result[:authenticated]
      render json: { authenticated: true, redirect_url: auth_nostr_callback_path }
      return
    end

    # The approval window is short (SESSION_EXPIRY). Once it lapses the record
    # leaves the `active` scope and no amount of further polling can ever
    # succeed — tell the client so it can offer a fresh QR instead of spinning.
    unless NostrAuthSession.active.exists?(session_id: session_id)
      render json: { authenticated: false, expired: true }
      return
    end

    render json: { authenticated: false }
  end

  def refresh_profile
    # Querying every relay in sequence takes seconds, so it happens in a job
    # instead of holding the request (and the user) hostage.
    user = current_user
    notice = if user
      RefreshUserProfileJob.perform_later(user.id)
      "Refreshing your profile from the relays in the background — reload in a moment to see it."
    end

    redirect_back fallback_location: dashboard_path, notice: notice
  end

  def callback
    pubkey_hex = if request.post?
      challenge = session.delete(:nostr_nip07_challenge)
      Nostr::AuthService.new.verify_nip07_auth(params[:signed_event], challenge)
    else
      result = Nostr::AuthService.new.check_session(session[:nostr_connect_session_id])
      result[:pubkey] if result&.dig(:authenticated)
    end

    unless pubkey_hex && Nostr::KeyConverter.valid_hex_pubkey?(pubkey_hex)
      redirect_to nostr_login_path, alert: "Authentication failed: Proof is invalid or expired"
      return
    end

    user = Nostr::AuthService.new.find_or_create_user(pubkey_hex)
    complete_authentication!(user)

    redirect_to dashboard_path, notice: "Welcome, #{user.display_name_or_npub}!"
  end

  def destroy
    consume_pending_sessions!
    reset_session
    redirect_to nostr_login_path, notice: "Logged out successfully"
  end

  private

  def rate_limit_exceeded
    response.set_header("Retry-After", "60")
    render_unavailable(:too_many_requests, "Slow down a moment",
                      "You have requested a few login codes in quick succession. Wait about a minute, then try again.")
  end

  def render_unavailable(status, title, message)
    @unavailable_title = title
    @unavailable_message = message
    render "sessions/unavailable", status: status
  end

  def pending_nip46_session
    NostrAuthSession.active.find_by(session_id: session[:nostr_connect_session_id])
  end

  def consume_pending_sessions!
    pending_nip46_session&.consume!
  end

  def complete_authentication!(user)
    consume_pending_sessions!
    reset_session
    session[:user_id] = user.id
  end
end
