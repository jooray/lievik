# frozen_string_literal: true

module Channels
  # "Rate all": queue an unrated sweep for every channel of the user. Shared by
  # the dashboard button and the app API. Returns the number of channels.
  module RateAll
    def self.call(user)
      channels = user.channels.to_a
      channels.each { |channel| RateEventsJob.perform_later(channel.id) }
      channels.size
    end

    def self.notice(count)
      I18n.t("dashboard.rate_all.queued", count: count)
    end
  end
end
