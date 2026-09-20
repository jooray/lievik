# frozen_string_literal: true

require "securerandom"

module Nostr
  class AuthService
    # Approval window: the QR/listener stays valid only this long. Kept short so
    # an abandoned login frees its worker thread and capacity slot quickly rather
    # than pinning them for the old 30-minute TTL.
    SESSION_EXPIRY = ENV.fetch("NOSTR_AUTH_WINDOW_MINUTES", 5).to_i.minutes
    NIP07_MAX_AGE = 5.minutes

    def initialize
      @config = Rails.application.config_for(:lievik)
      @auth_relays = @config.dig(:nostr, :auth_relays) ||
                     [@config.dig(:nostr, :auth_relay)].compact.presence ||
                     ["wss://relay.nsec.app"]
    end

    # Generate NIP-46 connection URI for QR code
    def generate_connect_uri
      keygen = ::Nostr::Keygen.new
      keypair = keygen.generate_key_pair
      secret = SecureRandom.hex(32)
      session_id = SecureRandom.uuid

      pubkey_hex = keypair.public_key.to_s
      privkey_hex = keypair.private_key.to_s

      auth_session = NostrAuthSession.create!(
        session_id: session_id,
        temp_pubkey: pubkey_hex,
        temp_privkey: privkey_hex,
        secret: secret,
        relay_url: @auth_relays.to_json,
        expires_at: SESSION_EXPIRY.from_now
      )

      # Build nostrconnect URI with multiple relay params
      app_name = "Lievik"
      relay_params = @auth_relays.map { |r| "relay=#{CGI.escape(r)}" }.join("&")
      uri = "nostrconnect://#{pubkey_hex}?#{relay_params}&secret=#{secret}&name=#{CGI.escape(app_name)}"

      {
        uri: uri,
        session_id: session_id,
        relay_urls: @auth_relays
      }
    end

    # Start a signer-initiated (bunker://) login. The user pastes a URI naming
    # the signer and its relays, so unlike nostrconnect we already know who we
    # are talking to and we send the first message.
    #
    # Returns { session_id:, relay_urls: } or nil when the URI is unusable.
    def start_bunker_session(bunker_uri)
      pointer = KeyConverter.parse_bunker_uri(bunker_uri)
      return nil if pointer.nil?

      # Talk to the signer's relays *and* ours. The pointer is stored as the
      # signer advertised it, but transport unions both: a signer that advertises
      # one relay which is down is otherwise unreachable, and our auth relays are
      # already known-good for ephemeral kind-24133 traffic.
      relays = Security::EgressGuard.filter_relay_urls(pointer[:relays] | @auth_relays, max: 6)
      return nil if relays.empty?

      keypair = ::Nostr::Keygen.new.generate_key_pair
      session_id = SecureRandom.uuid

      NostrAuthSession.create!(
        session_id: session_id,
        flow: "bunker",
        signer_pubkey: pointer[:pubkey],
        temp_pubkey: keypair.public_key.to_s,
        temp_privkey: keypair.private_key.to_s,
        # A bunker URI may carry no secret. `secret` is NOT NULL and the
        # nostrconnect flow compares against it, so store a value that can never
        # equal a signer's reply and let the bunker branch decide what to send.
        secret: pointer[:secret].presence || "",
        relay_url: relays.to_json,
        expires_at: SESSION_EXPIRY.from_now
      )

      { session_id: session_id, relay_urls: relays }
    end

    # Check if a NIP-46 session has been authenticated
    def check_session(session_id)
      auth_session = NostrAuthSession.active.find_by(session_id: session_id)
      return nil unless auth_session

      if auth_session.authenticated?
        { authenticated: true, pubkey: auth_session.authenticated_user_pubkey }
      else
        { authenticated: false }
      end
    end

    # Find or create user from pubkey (called after successful auth)
    def find_or_create_user(pubkey_hex)
      npub = KeyConverter.hex_to_npub(pubkey_hex)

      # Two browser tabs (or a retried callback) can hit this at the same moment
      # for one pubkey; find_or_initialize_by then races into RecordNotUnique and
      # 500s the callback. create_or_find_by! lets the unique index arbitrate.
      user = ::User.find_by(pubkey_hex: pubkey_hex)
      user ||= begin
        ::User.create!(pubkey_hex: pubkey_hex, npub: npub)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        # The other login won; adopt its record rather than blowing up the callback.
        ::User.find_by(pubkey_hex: pubkey_hex) || raise(e)
      end

      if user.previously_new_record?
        # Create the manual source for genuinely new users only, and tolerate a
        # concurrent login having created it already.
        begin
          user.sources.create!(
            source_type: :manual,
            identifier: "manual",
            name: "Manual entries",
            description: "Manually entered content",
            distance: 1
          )
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          Rails.logger.info("Manual source already exists for user #{user.id}")
        end
      end

      # Profile fetching is sequential relay IO (seconds per relay) — it happens
      # in the background so login itself stays fast.
      RefreshUserProfileJob.perform_later(user.id) if user.display_name.blank?

      user
    end

    # Verify a recent NIP-07 proof bound to a challenge stored in the Rails session.
    #
    # `domain` binds the proof to the host that issued the challenge, so a proof
    # signed for another site can never be presented here. It is verified when
    # the event carries a `domain` tag and not required when it does not: the
    # tag ships in the same deploy as the JS that produces it, and a browser
    # holding a stale bundle would otherwise be locked out until it reloaded.
    # Once a release has been out long enough that no stale bundles remain,
    # make the tag mandatory.
    def verify_nip07_auth(signed_event, challenge, domain: nil)
      return false if signed_event.blank? || challenge.blank?

      begin
        event_data = JSON.parse(signed_event)
        return false unless EventValidator.valid?(event_data, kind: 22_242)
        return false unless event_data["created_at"].between?(NIP07_MAX_AGE.ago.to_i, 1.minute.from_now.to_i)
        return false unless event_data["content"] == "Sign in to Lievik"
        return false unless event_data["tags"].include?(["challenge", challenge])

        signed_domain = Array(event_data["tags"]).find { |t| t.is_a?(Array) && t.first == "domain" }&.second
        if signed_domain.present? && domain.present? && !signed_domain.casecmp?(domain)
          Rails.logger.warn("NIP-07 proof signed for #{signed_domain.inspect}, expected #{domain.inspect}")
          return false
        end

        event_data["pubkey"].downcase
      rescue JSON::ParserError, TypeError => e
        Rails.logger.error("NIP-07 auth verification failed: #{e.message}")
        false
      end
    end

    # Cleanup expired sessions
    def cleanup_expired_sessions
      NostrAuthSession.cleanup_expired!
    end
  end
end
