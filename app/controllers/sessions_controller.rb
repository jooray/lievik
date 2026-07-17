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
      render plain: "Authentication is temporarily at capacity. Please try again shortly.", status: :service_unavailable
      return
    end

    begin
      NostrAuthSession.cleanup_expired!
      if NostrAuthSession.active.where(authenticated_pubkey: nil).count >= MAX_ACTIVE_AUTH_SESSIONS
        render plain: "Authentication is temporarily at capacity. Please try again shortly.", status: :service_unavailable
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
      render json: { authenticated: false, error: "No pending session" }
      return
    end

    # DB-only check — background job handles the relay subscription
    result = Nostr::AuthService.new.check_session(session_id)

    if result && result[:authenticated]
      render json: { authenticated: true, redirect_url: auth_nostr_callback_path }
      return
    end

    render json: { authenticated: false }
  end

  def refresh_profile
    user = current_user
    if user
      profile = Nostr::ProfileFetcher.new.fetch(user.pubkey_hex)
      if profile
        user.update!(
          display_name: profile[:display_name],
          username: profile[:username],
          about: profile[:about],
          picture_url: profile[:picture]
        )
        notice = "Profile updated from relays!"
      else
        notice = "Could not fetch profile from relays."
      end
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
    render plain: "Too many authentication attempts. Please try again shortly.", status: :too_many_requests
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
