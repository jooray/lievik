# frozen_string_literal: true

module ChannelEvents
  # Bulk actions on a channel's queue: mark used / unused and re-rate. Shared by
  # ChannelEventsController (web) and Api::V1::ChannelEventsController, so both
  # scope ids the same way and show the same notice.
  #
  # Every action returns a Result; `ok` false means nothing was done and
  # `message` is the alert to show.
  class BulkActions
    Result = Struct.new(:ok, :count, :message, keyword_init: true) do
      def ok? = ok
    end

    # `event_ids` is either an array of checkbox values or a JSON-encoded array
    # from the bulk-select Stimulus controller (or a JSON body from the app). A
    # hand-crafted request can send anything at all, so never let JSON.parse
    # (or its result) blow up the action.
    def self.parse_event_ids(raw)
      return [] if raw.blank?

      values = if raw.is_a?(String)
        begin
          JSON.parse(raw)
        rescue JSON::ParserError, TypeError
          []
        end
      else
        raw
      end

      Array.wrap(values).reject { |v| v.blank? || !v.to_s.match?(/\A\d+\z/) }
    end

    def initialize(channel, user)
      @channel = channel
      @user = user
    end

    def mark_used(raw_event_ids)
      event_ids = self.class.parse_event_ids(raw_event_ids)
      return no_selection if event_ids.empty?

      count = @channel.channel_events.where(event_id: event_ids).mark_all_used!
      Result.new(ok: true, count: count, message: I18n.t("channel_events.bulk_mark_used.notice", count: count))
    end

    def mark_unused(raw_event_ids)
      event_ids = self.class.parse_event_ids(raw_event_ids)
      return no_selection if event_ids.empty?

      count = @channel.channel_events.where(event_id: event_ids).mark_all_unused!
      Result.new(ok: true, count: count, message: I18n.t("channel_events.bulk_mark_unused.notice", count: count))
    end

    # The ids go through the user's own events: event ids are sequential, so an
    # unscoped list would let a caller rate another user's events into this
    # channel. RateEventsJob splits a long list into batches itself.
    def rate(raw_event_ids)
      event_ids = self.class.parse_event_ids(raw_event_ids)
      return no_selection if event_ids.empty?

      event_ids = @user.events.where(id: event_ids).pluck(:id)
      return no_selection if event_ids.empty?

      RateEventsJob.perform_later(@channel.id, event_ids)
      Result.new(ok: true, count: event_ids.size, message: I18n.t("channel_events.bulk_rate.notice", count: event_ids.size))
    end

    private

    def no_selection
      Result.new(ok: false, count: 0, message: I18n.t("channel_events.no_selection"))
    end
  end
end
