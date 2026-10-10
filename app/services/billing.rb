# frozen_string_literal: true

# Paid access on the hosted instance, through the shared nostr-billing service
# (vendor/gems/nostr_billing). Ingestion, rating and the AI features need a
# trial or paid time; browsing and configuring do not.
#
# Billing is off unless BILLING_API_URL is set: everything is then allowed and
# the billing pages answer 404, so a self-hosted install behaves as before.
# Specs get a disabled gate by default and turn it on with `stub_billing`.
module Billing
  PRODUCT = "lievik"
  # Plans this app sells: its own and the bundle.
  PLANS = [ PRODUCT, "all-access" ].freeze

  # Reads Rails.cache on every call, so a spec that swaps the cache store is
  # seen by a gate built earlier.
  module Cache
    def self.read(key) = Rails.cache.read(key)
    def self.write(key, value, expires_in: nil) = Rails.cache.write(key, value, expires_in: expires_in)
    def self.delete(key) = Rails.cache.delete(key)
  end

  class << self
    attr_writer :gate

    def gate
      @gate ||= build
    end

    def enabled?
      gate.enabled?
    end

    def status(user)
      gate.status(user.npub)
    end

    # Whether ingestion, rating and AI may run for this user. Jobs ask this; it
    # never starts a trial.
    def allows?(user)
      !enabled? || status(user).allows?
    end

    # The "first activation" hook for explicit user actions: starts the trial
    # when the user never had one, and catches up on what was paused when that
    # turns access on. Never call it from a job.
    def activate(user)
      return gate.status(user.npub) unless enabled?

      before = status(user)
      after = gate.activate(user.npub)
      Billing::Resume.call(user) if !before.allows? && after.allows?
      after
    end

    private

    def build
      if Rails.env.test?
        NostrBilling::Gate.new(product: PRODUCT, client: nil, cache: Cache)
      else
        NostrBilling.from_env(product: PRODUCT, cache: Cache, logger: Rails.logger)
      end
    end
  end
end
