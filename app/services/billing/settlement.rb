# frozen_string_literal: true

module Billing
  # Settles the charges a ledger remembers (billing settles each from BTCPay
  # when its webhook has not arrived yet). Run when the payer comes back to the
  # web billing page, and when the app opens or polls billing.
  module Settlement
    Result = Struct.new(:snapshot, :settled, :notice, keyword_init: true) do
      def settled? = settled
    end

    def self.check(user, ledger)
      settled = Billing.gate.check_charges(user.npub, ledger).first
      return Result.new(snapshot: Billing.status(user), settled: false) unless settled

      paid(user, settled[:snapshot])
    end

    # One charge, only if this ledger created it. nil when it did not.
    def self.check_one(user, ledger, invoice_id)
      return nil unless ledger.owns?(invoice_id)

      result = Billing.gate.charge(user.npub, invoice_id.to_s)
      if result[:settled]
        ledger.forget(invoice_id)
        return paid(user, result[:snapshot])
      end
      ledger.forget(invoice_id) if NostrBilling::Gate::DEAD_INVOICE_STATUSES.include?(result[:status])
      Result.new(snapshot: result[:snapshot], settled: false)
    rescue NostrBilling::BadRequest
      ledger.forget(invoice_id)
      Result.new(snapshot: Billing.status(user), settled: false)
    rescue NostrBilling::Error => e
      Rails.logger.warn("[billing] checking charge #{invoice_id} failed: #{e.message}")
      Result.new(snapshot: Billing.status(user), settled: false)
    end

    # The webhook may have settled it first, so "did the user lack access
    # before" cannot be told from here. Catching up is cheap and the jobs'
    # locks keep it from doubling work.
    def self.paid(user, snapshot)
      Billing::Resume.call(user)
      Result.new(snapshot: snapshot, settled: true,
                 notice: I18n.t("billing.paid", date: ApplicationController.helpers.billing_date(snapshot.until_time)))
    end
    private_class_method :paid
  end
end
