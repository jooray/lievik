# frozen_string_literal: true

# Background work costs money (relay traffic and AI rating), so on the hosted
# instance it runs only for users with a trial or paid time. A denied job logs
# one line and returns; it never raises, so it is not retried. Billing::Resume
# queues the work again when access starts.
module BillingGated
  private

  def billing_denies?(user, what)
    return false if user.nil? || Billing.allows?(user)

    Rails.logger.info("#{self.class.name}: skipped #{what} for user #{user.id}, no trial or paid time")
    true
  end
end
