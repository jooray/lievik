# frozen_string_literal: true

require "base64"

module Api
  module V1
    # GET /api/v1/sync — lets the app keep a local database and fetch only what
    # changed. See docs/API_V1.md "Sync".
    #
    # Two keyset-paginated streams share one opaque cursor (base64 JSON):
    #   events          ≤ EVENTS_PER_PAGE per page
    #   channel_events  ≤ CHANNEL_EVENTS_PER_PAGE per page
    # Initial sync (no `since`): everything in the window, events newest first
    # (published_at, id), channel_events by id. Incremental: rows whose
    # updated_at is after `since` (minus OVERLAP, so a row committed just
    # around the boundary is sent twice rather than never), by (updated_at,
    # id). The window is the user's largest source import_days, capped at
    # MAX_WINDOW_DAYS, anchored on the sync's server_time.
    #
    # `server_time` is fixed when the first page is served and repeated on
    # every page, so a client that stores it after the last page cannot skip
    # changes made while it was paging. Indexes: events (source_id,
    # updated_at, id) and channel_events (channel_id, updated_at, id).
    class SyncController < BaseController
      EVENTS_PER_PAGE = 500
      CHANNEL_EVENTS_PER_PAGE = 2000
      MAX_WINDOW_DAYS = 180
      DEFAULT_WINDOW_DAYS = 30
      OVERLAP = 5.seconds
      DONE = "done"

      class InvalidCursor < StandardError; end

      rescue_from InvalidCursor do
        render_error(:unprocessable_content, "invalid", t("api.errors.invalid_cursor"), details: { cursor: [ t("api.errors.invalid_cursor") ] })
      end

      def show
        state = params[:cursor].present? ? decode_cursor(params[:cursor]) : initial_state
        sources = current_user.sources.order(:id).to_a
        channels = current_user.channels.order(:id).to_a

        events, state["e"] = page_events(sources.map(&:id), state)
        channel_events, state["c"] = page_channel_events(channels.map(&:id), state)

        event_counts = Event.where(source_id: sources.map(&:id)).group(:source_id).count
        pending = Channels::PendingCounts.for(channels)

        render json: {
          server_time: Context.iso(time(state["t"])),
          sources: sources.map { |s| Serializers.source(s, event_count: event_counts[s.id] || 0) },
          channels: channels.map { |c| Serializers.channel(c, pending_count: pending[c.id] || 0) },
          events: EventSerializer.many(events, serialization_context),
          channel_events: channel_events.map { |ce| Serializers.channel_event(ce) },
          next_cursor: state["e"] == DONE && state["c"] == DONE ? nil : encode_cursor(state)
        }
      end

      private

      def initial_state
        since = parse_since(params[:since])
        now = Time.current
        days = (current_user.sources.map(&:settings_import_days).compact.map(&:to_i).max || DEFAULT_WINDOW_DAYS)
        days = DEFAULT_WINDOW_DAYS unless days.positive?
        window = now - [ days, MAX_WINDOW_DAYS ].min.days
        { "v" => 1, "t" => iso6(now), "s" => since && iso6(since), "w" => iso6(window), "e" => nil, "c" => nil }
      end

      def parse_since(value)
        return nil if value.blank?

        Time.iso8601(value.to_s)
      rescue ArgumentError
        raise InvalidCursor
      end

      # --- events ---------------------------------------------------------------

      def page_events(source_ids, state)
        return [ [], DONE ] if state["e"] == DONE || source_ids.empty?

        scope = Event.where(source_id: source_ids).where("events.published_at >= ?", time(state["w"]))
        position = state["e"]

        if (since = time(state["s"]))
          scope = scope.where("events.updated_at > ?", since - OVERLAP)
          if position
            at, id = keyset(position)
            scope = scope.where("events.updated_at > ? OR (events.updated_at = ? AND events.id > ?)", at, at, id)
          end
          scope = scope.order(Arel.sql("events.updated_at ASC, events.id ASC"))
          column = :updated_at
        else
          if position
            at, id = keyset(position)
            scope = scope.where("events.published_at < ? OR (events.published_at = ? AND events.id < ?)", at, at, id)
          end
          scope = scope.order(Arel.sql("events.published_at DESC, events.id DESC"))
          column = :published_at
        end

        rows = scope.includes(:source, channel_events: :channel).limit(EVENTS_PER_PAGE + 1).to_a
        return [ rows, DONE ] if rows.size <= EVENTS_PER_PAGE

        rows = rows.first(EVENTS_PER_PAGE)
        last = rows.last
        [ rows, [ iso6(last.public_send(column)), last.id ] ]
      end

      # --- channel events -----------------------------------------------------

      def page_channel_events(channel_ids, state)
        return [ [], DONE ] if state["c"] == DONE || channel_ids.empty?

        scope = ChannelEvent.where(channel_id: channel_ids)
          .where(event_id: Event.where("events.published_at >= ?", time(state["w"])).select(:id))
        position = state["c"]

        if (since = time(state["s"]))
          scope = scope.where("channel_events.updated_at > ?", since - OVERLAP)
          if position
            at, id = keyset(position)
            scope = scope.where("channel_events.updated_at > ? OR (channel_events.updated_at = ? AND channel_events.id > ?)", at, at, id)
          end
          scope = scope.order(Arel.sql("channel_events.updated_at ASC, channel_events.id ASC"))
        else
          scope = scope.where("channel_events.id > ?", keyset(position).last) if position
          scope = scope.order("channel_events.id ASC")
        end

        rows = scope.limit(CHANNEL_EVENTS_PER_PAGE + 1).to_a
        return [ rows, DONE ] if rows.size <= CHANNEL_EVENTS_PER_PAGE

        rows = rows.first(CHANNEL_EVENTS_PER_PAGE)
        last = rows.last
        [ rows, [ iso6(last.updated_at), last.id ] ]
      end

      # --- cursor ---------------------------------------------------------------

      def encode_cursor(state)
        Base64.urlsafe_encode64(state.to_json, padding: false)
      end

      def decode_cursor(raw)
        state = JSON.parse(Base64.urlsafe_decode64(raw.to_s))
        raise InvalidCursor unless state.is_a?(Hash) && state["v"] == 1 && state["t"] && state["w"]

        [ state["e"], state["c"] ].each do |position|
          next if position.nil? || position == DONE

          keyset(position)
        end
        time(state["t"]) && time(state["w"]) && time(state["s"])
        state
      rescue ArgumentError, JSON::ParserError
        raise InvalidCursor
      end

      def keyset(position)
        raise InvalidCursor unless position.is_a?(Array) && position.size == 2 && position[1].is_a?(Integer)

        [ time(position[0]), position[1] ]
      end

      def time(value)
        value.nil? ? nil : Time.iso8601(value.to_s)
      rescue ArgumentError
        raise InvalidCursor
      end

      def iso6(time)
        time.utc.iso8601(6)
      end
    end
  end
end
