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

      user = ::User.find_or_initialize_by(pubkey_hex: pubkey_hex)

      # If new user or profile is missing data, try to fetch it
      if user.new_record? || user.display_name.blank?
        user.npub = npub

        # Fetch profile from relays
        profile = ProfileFetcher.new.fetch(pubkey_hex)
        if profile
          user.display_name = profile[:display_name]
          user.username = profile[:username]
          user.about = profile[:about]
          user.picture_url = profile[:picture]
        end

        user.save!

        # Create manual source for the user only if it's a new record
        if user.previously_new_record?
          user.sources.create!(
            source_type: :manual,
            identifier: "manual",
            name: "Manual entries",
            description: "Manually entered content",
            distance: 1
          )
        end
      end

      user
    end

    # Verify a recent NIP-07 proof bound to a challenge stored in the Rails session.
    def verify_nip07_auth(signed_event, challenge)
      return false if signed_event.blank? || challenge.blank?

      begin
        event_data = JSON.parse(signed_event)
        return false unless EventValidator.valid?(event_data, kind: 22_242)
        return false unless event_data["created_at"].between?(NIP07_MAX_AGE.ago.to_i, 1.minute.from_now.to_i)
        return false unless event_data["content"] == "Sign in to Lievik"
        return false unless event_data["tags"].include?(["challenge", challenge])

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
