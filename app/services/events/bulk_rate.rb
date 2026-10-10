# frozen_string_literal: true

module Events
  # "Rate" on the events list: an explicit selection, or else everything the
  # filter matches, across every channel of the user, capped at
  # MAX_BULK_RATE_EVENTS (most recent kept). Shared by EventsController and the
  # app API so the cap and the notice text cannot drift apart.
  class BulkRate
    MAX_EVENTS = RateEventsJob::MAX_BULK_RATE_EVENTS

    Result = Struct.new(:ok, :count, :message, keyword_init: true) do
      def ok? = ok
    end

    # `event_ids` arrives as an array of checkbox values, but a hand-crafted or
    # buggy request can send a bare string (or a JSON-encoded array from the
    # bulk-select Stimulus controller). Never call Array methods on it blindly.
    def self.extract_event_ids(raw)
      values = case raw
      when Array
        raw
      when String
        stripped = raw.strip
        if stripped.start_with?("[")
          begin
            JSON.parse(stripped)
          rescue JSON::ParserError
            []
          end
        else
          stripped.split(",")
        end
      when ActionController::Parameters
        raw.to_unsafe_h.values
      else
        []
      end

      Array(values).flatten.map { |v| v.to_s.strip }.compact_blank.uniq
    end

    def initialize(user, event_ids: nil, filter: {})
      @user = user
      @requested_ids = self.class.extract_event_ids(event_ids)
      @filter = filter
    end

    def call
      explicit_selection = @requested_ids.any?

      # An explicit selection rates exactly those events (always through the
      # user's own events); otherwise what the user is looking at.
      scope = explicit_selection ? @user.events.where(id: @requested_ids).recent : Events::Filter.call(@user, @filter)

      matching_count = scope.count
      return failure("events.bulk_rate.no_match") if matching_count.zero?

      # `recent` orders newest first, so the cap keeps the most recent N.
      event_ids = scope.limit(MAX_EVENTS).pluck(:id)
      skipped = matching_count - event_ids.size
      channel_count = @user.channels.count
      return failure("events.bulk_rate.no_channels") if channel_count.zero?

      @user.channels.find_each do |channel|
        RateEventsJob.enqueue_batches(channel.id, event_ids)
      end

      channels_text = I18n.t("events.bulk_rate.channels", count: channel_count)
      key = explicit_selection ? "events.bulk_rate.queued_selected" : "events.bulk_rate.queued_matching"
      notice = I18n.t(key, count: event_ids.size, channels: channels_text)
      notice = [ notice, I18n.t("events.bulk_rate.skipped", count: skipped, max: MAX_EVENTS) ].join(" ") if skipped > 0

      Result.new(ok: true, count: event_ids.size, message: notice)
    end

    private

    def failure(key)
      Result.new(ok: false, count: 0, message: I18n.t(key))
    end
  end
end
