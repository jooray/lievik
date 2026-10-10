# frozen_string_literal: true

module Nostr
  # Admission for new NIP-46 logins (nostrconnect QR / deep link, and
  # bunker://). Shared by the web SessionsController and the app API so both
  # obey the same capacity cap and serialization.
  #
  # One multiplexed supervisor (Nostr::Nip46Supervisor) serves every pending
  # login at once with O(1) DB/WebSocket connections, so admission is not bound
  # to one worker per login. The cap just guards memory / relay subscription
  # fan-out.
  module LoginAdmission
    MAX_ACTIVE_AUTH_SESSIONS = ENV.fetch("MAX_ACTIVE_NOSTR_AUTH_SESSIONS", 50).to_i
    ADMISSION_KEY = "nostr-auth-session-admission"

    # Creates a nostrconnect session and makes sure the supervisor runs.
    # Returns the AuthService#generate_connect_uri hash, or :busy when another
    # login is being admitted right now or too many are pending. Yields the
    # connect data inside the admission window (the web stores its session ids
    # there). A failure after the session was created destroys it again.
    def self.start_connect(max_active: MAX_ACTIVE_AUTH_SESSIONS)
      # Serialize session creation so a burst can't slip past the capacity check.
      admission_token = SecureRandom.hex(16)
      admitted = Rails.cache.write(ADMISSION_KEY, admission_token, expires_in: 10.seconds, unless_exist: true)
      return :busy unless admitted

      connect_data = nil
      begin
        NostrAuthSession.cleanup_expired!
        return :busy if NostrAuthSession.active.where(authenticated_pubkey: nil).count >= max_active

        connect_data = Nostr::AuthService.new.generate_connect_uri
        yield connect_data if block_given?

        # Ensure the multiplexed listener is running — it will pick up this
        # session from the DB within ~1s. Polls just check the DB for the
        # persisted result.
        Nip46SupervisorJob.ensure_running
        connect_data
      rescue StandardError
        NostrAuthSession.find_by(session_id: connect_data&.dig(:session_id))&.destroy!
        raise
      ensure
        Rails.cache.delete(ADMISSION_KEY) if Rails.cache.read(ADMISSION_KEY) == admission_token
      end
    end

    # bunker:// login. Returns { session_id:, relay_urls: } or nil for an
    # unusable URI.
    def self.start_bunker(bunker_uri)
      result = Nostr::AuthService.new.start_bunker_session(bunker_uri)
      return nil if result.nil?

      Nip46SupervisorJob.ensure_running
      result
    end
  end
end
