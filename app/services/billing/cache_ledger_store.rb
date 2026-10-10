# frozen_string_literal: true

module Billing
  # The hash-like store NostrBilling::ChargeLedger needs, kept per user in
  # Rails.cache. The web keeps the ledger in the cookie session; the app API
  # has no session, so the charges a user creates through the API are
  # remembered here (and only those can be polled through the API).
  class CacheLedgerStore
    TTL = NostrBilling::ChargeLedger::MAX_AGE.seconds

    def initialize(user)
      @key = "api-billing-ledger:#{user.id}"
    end

    def [](name)
      (Rails.cache.read(@key) || {})[name]
    end

    def []=(name, value)
      data = (Rails.cache.read(@key) || {}).merge(name => value)
      Rails.cache.write(@key, data, expires_in: TTL)
    end
  end
end
