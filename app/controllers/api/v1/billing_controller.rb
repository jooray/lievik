# frozen_string_literal: true

module Api
  module V1
    # Plans, trial and payment (the web's /billing). 404 when billing is not
    # configured. The web remembers its charges in the cookie session; the API
    # keeps a per-user ledger in Rails.cache (Billing::CacheLedgerStore), so
    # only charges created through the API can be polled here.
    class BillingController < BaseController
      before_action :require_billing!

      def show
        settlement = Billing::Settlement.check(current_user, ledger)
        plans = Billing.gate.plans
        body = {
          status: Serializers.billing_status(settlement.snapshot, current_user),
          plans: (plans&.dig("plans") || {}).slice(*Billing::PLANS).map do |plan, details|
            { plan: plan, sats: details["sats"], days: details["days"] }
          end,
          min_sats: Billing::Checkout::MIN_SATS,
          max_sats: Billing::Checkout::MAX_SATS,
          pending_charges: ledger.ids.map { |id| { invoice_id: id, plan: ledger.plan(id), checkout_url: ledger.checkout_url(id) } }
        }
        body[:notice] = settlement.notice if settlement.settled?
        render json: body
      end

      def start_trial
        snapshot = Billing.activate(current_user)
        notice = snapshot.trial? ? t("billing.trial_started", date: ApplicationController.helpers.billing_date(snapshot.until_time)) : nil
        render json: { status: Serializers.billing_status(snapshot, current_user), notice: notice }
      end

      def create_charge
        result = Billing::Checkout.call(current_user, plan: params[:plan], sats: params[:sats], redirect_url: billing_app_return_url, ledger: ledger)
        unless result.ok?
          return render_error(:service_unavailable, "billing_unavailable", result.error) if result.reason == :unavailable

          return render_error(:unprocessable_content, "invalid", result.error)
        end

        render json: { invoice_id: result.invoice_id, checkout_url: result.checkout_url }
      end

      def charge
        settlement = Billing::Settlement.check_one(current_user, ledger, params[:invoice_id])
        return render_not_found unless settlement

        body = { settled: settlement.settled?, status: Serializers.billing_status(settlement.snapshot, current_user) }
        body[:notice] = settlement.notice if settlement.settled?
        render json: body
      end

      private

      def require_billing!
        render_not_found unless Billing.enabled?
      end

      def ledger
        @ledger ||= NostrBilling::ChargeLedger.new(Billing::CacheLedgerStore.new(current_user))
      end
    end
  end
end
