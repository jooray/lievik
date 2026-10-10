# frozen_string_literal: true

# Gates the actions that start paid work on the hosted instance. With billing
# disabled every check returns at once.
#
#   requires_paid_access only: [...]
#     Buttons that queue rating or ingestion. They are explicit user actions,
#     so they start the trial; a user who still has no access is sent to the
#     billing page instead of queuing jobs that would be skipped.
#
#   requires_paid_ai kind: "chat", prompt: :question, only: [...]
#     AI requests answered as JSON or SSE. The first one starts the trial,
#     unless the named prompt param is blank. Denials are real HTTP statuses
#     with a JSON body, sent before any stream header, so the page can tell a
#     paywall from a dropped stream:
#       402 paywall              no trial and no paid time
#       429 daily_cap            the daily safety cap
#       503 billing_unavailable  billing is down and nothing cached says the user paid
#
# Included by ApplicationController (web) and Api::V1::BaseController (app).
# The two differ only in the hooks below: the web redirects a denied button to
# the billing page, the app API answers 402 paywall JSON.
module BillingGate
  extend ActiveSupport::Concern

  class_methods do
    def requires_paid_access(**options)
      before_action :require_paid_access!, **options
    end

    def requires_paid_ai(kind:, prompt: nil, **options)
      before_action(**options) { require_paid_ai!(kind, prompt) }
    end
  end

  private

  def require_paid_access!
    return unless Billing.enabled?
    return if Billing.activate(current_user).allows?

    deny_paid_access!
  end

  # Hook: what a denied button does. Overridden by the app API.
  def deny_paid_access!
    redirect_to billing_path, alert: t("billing.denied")
  end

  # Hook: the billing page a paywall denial points at.
  def billing_denial_url
    billing_path
  end

  def require_paid_ai!(kind, prompt_param)
    return unless Billing.enabled?

    # A request without its prompt must not burn the one-time trial.
    activates = prompt_param.nil? || params[prompt_param].present?
    snapshot = activates ? Billing.activate(current_user) : Billing.status(current_user)
    unless snapshot.allows?
      return snapshot.unknown? ? deny_billing_unavailable : deny_paywall
    end

    case Billing.gate.consume(current_user.npub, kind: kind, key: request.request_id)
    when :allowed then nil
    when :capped then render_billing_denial(:too_many_requests, "daily_cap", t("billing.daily_cap"))
    when :not_entitled then deny_paywall
    else deny_billing_unavailable
    end
  end

  # The 402 carries the billing page, not a checkout link, so blocked clicks do
  # not create BTCPay invoices.
  def deny_paywall
    render_billing_denial(:payment_required, "paywall", t("billing.paywall"), billing_url: billing_denial_url)
  end

  def deny_billing_unavailable
    render_billing_denial(:service_unavailable, "billing_unavailable", t("billing.unavailable"))
  end

  def render_billing_denial(status, code, message, **extra)
    render json: { error: message, code: code, **extra }, status: status
  end
end
