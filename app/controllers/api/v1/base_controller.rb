# frozen_string_literal: true

module Api
  module V1
    # Base of the app API (docs/API_V1.md is the contract). JSON in and out,
    # bearer-token auth, the same billing gate and translations as the web.
    #
    # Shared-logic rule: these controllers hold no business logic of their own.
    # Anything the web also does lives in a service/query object (app/services)
    # that both the web controller and the API controller call.
    class BaseController < ActionController::API
      include AbstractController::Translation
      include ApiTokenAuthentication
      include BillingGate

      PER_PAGE = 50
      MAX_PER_PAGE = 100

      # Per token (per IP without one). Scoped app-wide, not per controller.
      rate_limit to: 300, within: 1.minute, by: :rate_limit_key, name: "requests", scope: "api-v1",
                 with: :render_rate_limited

      around_action :switch_locale
      before_action :authenticate_api_token!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid do |e|
        render_invalid(e.record)
      end
      rescue_from ActionController::ParameterMissing do |e|
        render_error(:bad_request, "bad_request", t("api.errors.bad_request"), details: { e.param => [ t("api.errors.missing") ] })
      end

      private

      def current_api_token
        return @current_api_token if defined?(@current_api_token)

        @current_api_token = authenticate_bearer_token
      end

      def current_user
        current_api_token&.user
      end

      def authenticate_api_token!
        return if current_user

        render_error(:unauthorized, "unauthorized", t("api.errors.unauthorized"))
      end

      # ?locale= → Accept-Language → the user's saved locale → en. The app sends
      # its own UI language as Accept-Language; nothing is persisted here
      # (PATCH /me saves the user's choice).
      def switch_locale(&action)
        locale = request_locale || current_user&.locale || I18n.default_locale
        I18n.with_locale(locale, &action)
      end

      def request_locale
        supported_locale(params[:locale]) || accept_language_locale
      end

      def supported_locale(value)
        value = value.to_s.downcase
        I18n.available_locales.find { |l| l.to_s == value }
      end

      def accept_language_locale
        request.headers["Accept-Language"].to_s.split(",").each do |part|
          tag = part.split(";").first.to_s.strip.downcase
          locale = supported_locale(tag.split("-").first)
          return locale if locale
        end
        nil
      end

      # --- rendering ---------------------------------------------------------

      def render_error(status, code, message, details: nil)
        body = { error: message, code: code }
        body[:details] = details if details.present?
        render json: body, status: status
      end

      def render_not_found(_error = nil)
        render_error(:not_found, "not_found", t("api.errors.not_found"))
      end

      def render_invalid(record)
        render_error(:unprocessable_content, "invalid", record.errors.full_messages.to_sentence.presence || t("api.errors.invalid"),
                     details: record.errors.to_hash(false).transform_values { |messages| messages.uniq })
      end

      def render_rate_limited
        response.set_header("Retry-After", "60")
        I18n.with_locale(request_locale || I18n.default_locale) do
          render_error(:too_many_requests, "rate_limited", t("api.errors.rate_limited"))
        end
      end

      # A web action that answers with a flash alert (nothing done) answers
      # 422 here, with the same text.
      def render_alert(message, code: "invalid")
        render_error(:unprocessable_content, code, message)
      end

      # --- billing gate hooks (see BillingGate) ------------------------------

      # Buttons answer 402 paywall instead of redirecting to /billing.
      def deny_paid_access!
        render_billing_denial(:payment_required, "paywall", t("billing.denied"), billing_url: billing_denial_url)
      end

      # The web billing page, absolute: the app opens it in a browser.
      def billing_denial_url
        billing_url
      end

      # --- helpers -------------------------------------------------------------

      def serialization_context
        @serialization_context ||= Api::V1::Context.new(current_user)
      end

      def paginate(scope)
        per = params[:per].present? ? params[:per].to_i.clamp(1, MAX_PER_PAGE) : PER_PAGE
        scope.page(params[:page]).per(per)
      end

      def pagination_meta(relation)
        Serializers.pagination(relation)
      end

      def truthy_param?(name)
        ActiveModel::Type::Boolean.new.cast(params[name]) == true
      end
    end
  end
end
