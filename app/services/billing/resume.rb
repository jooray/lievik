# frozen_string_literal: true

module Billing
  # Jobs skipped while a user had no access are dropped, not retried. When
  # access starts (trial or payment), this queues what they would have done:
  # a refresh of every source and a sweep of unrated events per channel.
  module Resume
    def self.call(user)
      RefreshAllSourcesJob.perform_later(user.id)
      user.channels.find_each { |channel| RateEventsJob.perform_later(channel.id) }
    end
  end
end
