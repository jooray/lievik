# frozen_string_literal: true

module Api
  module V1
    # What the app needs before signing in: API and build versions, whether
    # billing is on, and the Android version gate.
    class MetaController < BaseController
      skip_before_action :authenticate_api_token!

      def show
        config = Rails.application.config_for(:lievik)
        render json: {
          api_version: 1,
          build_version: Lievik::BUILD_VERSION,
          instance_name: "Lievik",
          billing_enabled: Billing.enabled?,
          decision_rating_available: Ai::DecisionClient.configured?,
          locales: I18n.available_locales.map(&:to_s),
          android: {
            min_version_code: env_int("ANDROID_MIN_VERSION_CODE", 1),
            latest_version_code: env_int("ANDROID_LATEST_VERSION_CODE", env_int("ANDROID_MIN_VERSION_CODE", 1)),
            download_url: Api::V1::Context.new(nil).safe_url(ENV["ANDROID_DOWNLOAD_URL"])
          },
          nip46_relays: config.dig(:nostr, :auth_relays) || [ config.dig(:nostr, :auth_relay) ].compact
        }
      end

      private

      def env_int(name, default)
        Integer(ENV[name].presence || default)
      rescue ArgumentError, TypeError
        default
      end
    end
  end
end
