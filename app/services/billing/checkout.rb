# frozen_string_literal: true

module Billing
  # Creates a BTCPay charge for one of Billing::PLANS and remembers it in the
  # caller's ChargeLedger (the web session, or a per-user cache store for the
  # app API). Shared by BillingController and the app API.
  module Checkout
    MIN_SATS = 1_000
    MAX_SATS = 1_000_000

    Result = Struct.new(:ok, :invoice_id, :checkout_url, :error, :reason, keyword_init: true) do
      def ok? = ok
    end

    def self.call(user, plan:, sats:, redirect_url:, ledger:)
      plan = plan.to_s
      return failure(I18n.t("billing.errors.unknown_plan")) unless Billing::PLANS.include?(plan)

      sats = sats.presence&.to_i
      if sats && !(MIN_SATS..MAX_SATS).cover?(sats)
        return failure(I18n.t("billing.errors.sats_range", min: MIN_SATS, max: MAX_SATS))
      end

      charge = Billing.gate.create_charge(user.npub, plan: plan, sats: sats, redirect_url: redirect_url)
      checkout_url = safe_checkout_url(charge["checkout_url"])
      return failure(I18n.t("billing.errors.unavailable"), reason: :unavailable) unless checkout_url

      ledger.remember(charge["invoice_id"], checkout_url: checkout_url, plan: plan)
      Result.new(ok: true, invoice_id: charge["invoice_id"], checkout_url: checkout_url)
    rescue NostrBilling::Error => e
      Rails.logger.warn("[billing] charge for #{user.npub} failed: #{e.message}")
      failure(I18n.t("billing.errors.unavailable"), reason: :unavailable)
    end

    # Only an https checkout URL is followed.
    def self.safe_checkout_url(value)
      uri = URI.parse(value.to_s)
      uri.is_a?(URI::HTTPS) && uri.host.present? ? uri.to_s : nil
    rescue URI::InvalidURIError
      nil
    end

    # reason: :invalid (bad plan or amount) or :unavailable (billing failed)
    def self.failure(message, reason: :invalid)
      Result.new(ok: false, error: message, reason: reason)
    end
    private_class_method :failure
  end
end
