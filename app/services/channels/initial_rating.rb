# frozen_string_literal: true

module Channels
  # Back-rates recent events for a brand-new channel (web create form, AI
  # channel chat bulk create, and the app API).
  #
  # Rating an event costs up to 3 paid AI calls, so a new channel only rates a
  # bounded, most-recent slice (past 3 months, at most MAX_BULK_RATE_EVENTS),
  # enqueued in chunks; the rest can be rated later.
  module InitialRating
    MAX_EVENTS = RateEventsJob::MAX_BULK_RATE_EVENTS

    # Returns the number of events queued.
    def self.queue(channel)
      recent_event_ids = channel.user.events
        .where("events.published_at >= ?", 3.months.ago)
        .order(published_at: :desc)
        .limit(MAX_EVENTS)
        .pluck(:id)

      RateEventsJob.enqueue_batches(channel.id, recent_event_ids)
    end

    # The flash after creating a channel, for `queued` events.
    def self.created_notice(queued)
      if queued.zero?
        I18n.t("channels.create.notice")
      elsif queued >= MAX_EVENTS
        I18n.t("channels.create.notice_capped", count: queued)
      else
        I18n.t("channels.create.notice_queued", count: queued)
      end
    end
  end
end
