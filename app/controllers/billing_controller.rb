# frozen_string_literal: true

# Plans, trial and payment on the hosted instance. Answers 404 when billing is
# not configured (self-hosted).
#
# Paying redirects the form post straight to the BTCPay checkout, and BTCPay
# sends the payer back here once the invoice is paid. Billing does not
# authenticate users, so the session remembers which charges it created
# (NostrBilling::ChargeLedger); showing this page checks those, which also
# settles a payment whose webhook has not arrived yet.
class BillingController < ApplicationController
  MIN_SATS = Billing::Checkout::MIN_SATS
  MAX_SATS = Billing::Checkout::MAX_SATS

  before_action :require_billing!

  # The app-wide form-action 'self' would stop the redirect to BTCPay, whose
  # host this app does not know. The forms on this page only post here.
  content_security_policy only: :show do |policy|
    policy.form_action :self, :https
  end

  def show
    # Settles a returning payer's charges (shared with the app API).
    settlement = Billing::Settlement.check(current_user, ledger)
    @snapshot = settlement.snapshot
    flash.now[:notice] = settlement.notice if settlement.settled?
    @plans = Billing.gate.plans&.dig("plans")&.slice(*Billing::PLANS)
  end

  # The banner at the top of every page, loaded lazily so no page waits on
  # billing.
  def status
    @snapshot = Billing.status(current_user)
    render layout: false
  end

  def start_trial
    snapshot = Billing.activate(current_user)
    if snapshot.trial?
      redirect_to dashboard_path, notice: t("billing.trial_started", date: helpers.billing_date(snapshot.until_time))
    else
      redirect_to billing_path
    end
  end

  def create_charge
    result = Billing::Checkout.call(current_user, plan: params[:plan], sats: params[:sats], redirect_url: billing_url, ledger: ledger)
    return redirect_to(billing_path, alert: result.error) unless result.ok?

    redirect_to result.checkout_url, allow_other_host: true
  end

  private

  def require_billing!
    raise ActionController::RoutingError, "Not Found" unless Billing.enabled?
  end

  def ledger
    @ledger ||= NostrBilling::ChargeLedger.new(session)
  end
end
