# frozen_string_literal: true

# Specs run with billing off, like a self-hosted install. `stub_billing` turns
# it on for one example, backed by NostrBilling::MockClient and a MemoryStore
# (the test cache is a null store, which would hide every cached answer).
module BillingHelpers
  def stub_billing
    @billing_previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @billing = NostrBilling::MockClient.new
    Billing.gate = NostrBilling::Gate.new(product: Billing::PRODUCT, client: @billing, cache: Billing::Cache)
    @billing
  end

  def billing_calls(name)
    @billing.calls.select { |call| call.first == name }
  end
end

RSpec.configure do |config|
  config.include BillingHelpers
  config.after do
    Billing.gate = nil
    Rails.cache = @billing_previous_cache if @billing_previous_cache
  end
end
