# frozen_string_literal: true

module Api
  module V1
    # The signed-in user and their settings (the web's /user/edit).
    class MeController < BaseController
      USER_PARAMS = %i[system_prompt event_link_template naddr_link_template profile_link_template
                       default_content_style rating_engine locale].freeze

      def show
        render json: {
          user: Serializers.user(current_user),
          stats: Users::Stats.for(current_user),
          billing: Serializers.billing_status(Billing.status(current_user), current_user)
        }
      end

      def update
        current_user.update!(params.require(:user).permit(*USER_PARAMS))
        # Answer in the language the user just chose.
        I18n.with_locale(current_user.locale || I18n.locale) do
          render json: { user: Serializers.user(current_user), notice: t("users.update.notice") }
        end
      end

      def refresh_profile
        RefreshUserProfileJob.perform_later(current_user.id)
        render json: { notice: t("sessions.refresh_profile.notice") }
      end

      def reindex
        ReindexEmbeddingsJob.perform_later(current_user.id)
        render json: { notice: t("users.reindex.notice") }
      end
    end
  end
end
