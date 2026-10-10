# frozen_string_literal: true

module Api
  module V1
    # Sign-in for the app. Every signed-in device gets its own ApiToken, named
    # "App: <device name>" (listed and revocable in the web's token list).
    #
    # Signed challenge (NIP-55 Amber or any local signer): the challenge is
    # stored server side in Rails.cache, single-use, for CHALLENGE_TTL, and
    # verified by the same Nostr::AuthService#verify_nip07_auth as the web.
    #
    # NIP-46: the same NostrAuthSession / Nip46SupervisorJob machinery and
    # admission rules as the web (Nostr::LoginAdmission). There is no cookie
    # session to bind the login to, so the creator gets a secret poll token;
    # only its digest is stored.
    class AuthController < BaseController
      CHALLENGE_TTL = 5.minutes
      CHALLENGE_PREFIX = "api-auth-challenge:"
      DEVICE_NAME_MAX = 60
      # Signers differ in what they put in a kind-22242 proof's content; the
      # challenge and domain tags are what bind it. The contract names "".
      ACCEPTED_CONTENT = [ "", Nostr::AuthService::NIP07_CONTENT ].freeze

      skip_before_action :authenticate_api_token!, except: :destroy

      rate_limit to: 30, within: 1.minute, only: [ :challenge, :token ], name: "auth-challenge-ip", with: :render_rate_limited
      rate_limit to: 5, within: 1.minute, only: :nostrconnect, name: "nip46-ip", with: :render_rate_limited
      rate_limit to: 60, within: 1.minute, only: :nostrconnect, name: "nip46-global", by: -> { "global" }, with: :render_rate_limited
      rate_limit to: 10, within: 1.minute, only: :bunker, name: "bunker-ip", with: :render_rate_limited
      rate_limit to: 120, within: 1.minute, only: :poll, name: "nip46-poll-ip", with: :render_rate_limited

      def challenge
        challenge = SecureRandom.hex(32)
        Rails.cache.write(CHALLENGE_PREFIX + challenge, CHALLENGE_TTL.from_now.to_i, expires_in: CHALLENGE_TTL)
        render json: { challenge: challenge, domain: request.host, token_url: token_endpoint_url, expires_in: CHALLENGE_TTL.to_i }
      end

      def token
        event = signed_event_param
        challenge = challenge_tag(event)
        return auth_failed unless challenge && consume_challenge(challenge)

        # Apps sign a NIP-98 proof (kind 27235) for this endpoint; kind 22242
        # with a domain tag is still accepted from builds that predate it.
        service = Nostr::AuthService.new
        pubkey_hex = if event["kind"] == Nostr::AuthService::HTTP_AUTH_KIND
          service.verify_http_auth(event.to_json, challenge, url: token_endpoint_url)
        else
          service.verify_nip07_auth(event.to_json, challenge, domain: request.host, content: ACCEPTED_CONTENT, require_domain: true)
        end
        return auth_failed unless pubkey_hex && Nostr::KeyConverter.valid_hex_pubkey?(pubkey_hex)

        issue_token(pubkey_hex)
      end

      def destroy
        current_api_token.destroy!
        head :no_content
      end

      def nostrconnect
        session_token = SecureRandom.hex(32)
        connect = Nostr::LoginAdmission.start_connect do |data|
          NostrAuthSession.where(session_id: data[:session_id]).update_all(poll_token_digest: ApiToken.digest_for(session_token))
        end
        return render_busy if connect == :busy

        auth_session = NostrAuthSession.find_by!(session_id: connect[:session_id])
        render json: {
          session_id: connect[:session_id],
          poll_token: session_token,
          uri: connect[:uri],
          expires_at: Context.iso(auth_session.expires_at)
        }
      end

      def bunker
        result = Nostr::LoginAdmission.start_bunker(params[:bunker_uri])
        return render_error(:unprocessable_content, "invalid_link", t("sessions.bunker.invalid_link")) if result.nil?

        session_token = SecureRandom.hex(32)
        auth_session = NostrAuthSession.find_by!(session_id: result[:session_id])
        auth_session.update_columns(poll_token_digest: ApiToken.digest_for(session_token))
        render json: { session_id: result[:session_id], poll_token: session_token, expires_at: Context.iso(auth_session.expires_at) }
      end

      def poll
        auth_session = NostrAuthSession.find_by(session_id: params[:session_id].to_s)
        # Expired sessions are swept away eventually; gone means expired.
        return render(json: { status: "expired" }) unless auth_session
        return render_not_found unless poll_token_matches?(auth_session)

        return render(json: { status: "expired" }) if auth_session.consumed_at.present? || auth_session.expired?

        unless auth_session.authenticated?
          # Some signers answer by demanding the user authorize in a browser
          # first; without the URL the login just spins.
          return render(json: { status: "pending", auth_url: auth_session.auth_url.presence })
        end

        # Claim the session atomically: the token is issued exactly once even
        # when two polls race.
        claimed = NostrAuthSession.active.where(id: auth_session.id).update_all(consumed_at: Time.current) == 1
        return render(json: { status: "expired" }) unless claimed

        pubkey_hex = auth_session.authenticated_user_pubkey
        auth_session.reload.consume!
        return auth_failed unless Nostr::KeyConverter.valid_hex_pubkey?(pubkey_hex)

        issue_token(pubkey_hex, status: "authenticated")
      end

      private

      # The URL a NIP-98 proof's `u` tag names.
      def token_endpoint_url
        "#{request.base_url}/api/v1/auth/token"
      end

      def signed_event_param
        raw = params[:signed_event]
        raw = JSON.parse(raw) if raw.is_a?(String)
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        raw.is_a?(Hash) ? raw.deep_stringify_keys : nil
      rescue JSON::ParserError
        nil
      end

      def challenge_tag(event)
        return nil unless event && event["tags"].is_a?(Array)

        value = event["tags"].find { |t| t.is_a?(Array) && t.first == "challenge" }&.second
        value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/) ? value : nil
      end

      # Single-use: only the request whose delete actually removed the entry
      # may use it; the stored expiry guards against a store that keeps expired
      # rows around until they are swept.
      def consume_challenge(challenge)
        key = CHALLENGE_PREFIX + challenge
        expires_at = Rails.cache.read(key)
        return false unless expires_at

        Rails.cache.delete(key) && expires_at.to_i > Time.current.to_i
      end

      def poll_token_matches?(auth_session)
        digest = auth_session.poll_token_digest
        digest.present? && params[:poll_token].present? &&
          ActiveSupport::SecurityUtils.secure_compare(digest, ApiToken.digest_for(params[:poll_token].to_s))
      end

      def issue_token(pubkey_hex, **extra)
        user = Nostr::AuthService.new.find_or_create_user(pubkey_hex)
        token = ApiToken.generate(user, name: device_token_name)
        render json: { **extra, token: token.plain_token, user: Serializers.user(user) }
      end

      def device_token_name
        device = params[:device_name].to_s.gsub(/[[:cntrl:]]/, " ").squish.presence || "Android"
        "App: #{device}".truncate(DEVICE_NAME_MAX)
      end

      def auth_failed
        render_error(:unauthorized, "auth_failed", t("sessions.callback.failed"))
      end

      def render_busy
        render_error(:service_unavailable, "busy", t("sessions.unavailable_reasons.busy.message"))
      end
    end
  end
end
