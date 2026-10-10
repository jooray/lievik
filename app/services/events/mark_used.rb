# frozen_string_literal: true

module Events
  # "Mark as used" on one event's page: flips the chosen channel_events of
  # that event, only within the user's own channels. Shared by EventsController
  # and the app API.
  module MarkUsed
    Result = Struct.new(:ok, :count, :message, keyword_init: true) do
      def ok? = ok
    end

    def self.parse_ids(raw)
      if raw.is_a?(String) && raw.start_with?("[")
        JSON.parse(raw) rescue []
      else
        Array(raw).reject(&:blank?)
      end
    end

    def self.call(user, event, raw_channel_event_ids)
      ids = parse_ids(raw_channel_event_ids)
      return Result.new(ok: false, count: 0, message: I18n.t("events.bulk_mark_used.no_channels_selected")) if ids.empty?

      # A subquery rather than a join: MariaDB turns update_all over a join
      # into a multi-table UPDATE, where `updated_at` exists on both tables.
      count = ChannelEvent
        .where(id: ids, event: event, channel_id: user.channels.select(:id))
        .mark_all_used!

      Result.new(ok: true, count: count, message: I18n.t("events.bulk_mark_used.marked_used", count: count))
    end
  end
end
